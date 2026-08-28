# main.tf — oci-compute module

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

# ── Networking ──────────────────────────────────────────────────────
resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "${var.instance_display_name}-vcn"
  dns_label      = "rastaful"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.instance_display_name}-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.instance_display_name}-rt"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

# Security list: SSH from your IP only, all else inbound denied. No app
# ports opened — Cloudflare Tunnel connects outbound from the instance,
# never needs an inbound path (same BFF-proxy "no public backend port"
# logic as ADR 011, applied at the VM level here).
resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.instance_display_name}-seclist"
  freeform_tags  = var.freeform_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = var.operator_cidr
    protocol = "6" # TCP
    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "this" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = var.subnet_cidr
  display_name               = "${var.instance_display_name}-subnet"
  dns_label                  = "main"
  route_table_id             = oci_core_route_table.this.id
  security_list_ids          = [oci_core_security_list.this.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = var.freeform_tags
}

# ── Image lookup: latest Canonical Ubuntu 24.04 ARM (aarch64) ─────────
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ── Compute instance ────────────────────────────────────────────────
resource "oci_core_instance" "this" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  display_name        = var.instance_display_name
  shape               = "VM.Standard.A1.Flex"
  freeform_tags       = var.freeform_tags

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.this.id
    assign_public_ip = true
    display_name     = "${var.instance_display_name}-vnic"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {}))
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id] # don't force-replace on new image releases
  }
}
