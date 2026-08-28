# variables.tf — oci-compute module
# Provisions the oci-free environment (ADR 005, ADR 007): a single Ampere
# A1 (ARM) Always-Free instance running Coolify, which then manages the
# platform + app deployments via Docker Compose.

variable "compartment_id" {
  description = "OCI compartment OCID to create resources in"
  type        = string
}

variable "region" {
  description = "OCI region — prefer non-US for Always-Free ARM shape availability (Frankfurt/Singapore/Tokyo provision reliably; US regions frequently report 'Out of host capacity'). See ADR 007."
  type        = string
}

variable "availability_domain" {
  description = "Availability domain within the region (e.g. 'AbCd:EU-FRANKFURT-1-AD-1') — look up via `oci iam availability-domain list`"
  type        = string
}

variable "instance_display_name" {
  description = "Human-readable name for the instance"
  type        = string
  default     = "rastaful-oci-free"
}

variable "ocpus" {
  description = "OCPU count for the Ampere A1 Flex shape. ADR 007: 2 OCPU (Oracle cut the Always-Free allowance from 4/24 to 2/12 in June 2026)."
  type        = number
  default     = 2
}

variable "memory_in_gbs" {
  description = "Memory (GB) for the Ampere A1 Flex shape. ADR 007: 12GB."
  type        = number
  default     = 12
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size — Always Free tier covers up to 200GB total across boot + block volumes"
  type        = number
  default     = 100
}

variable "ssh_public_key" {
  description = "SSH public key for emergency access. Coolify is the normal management path (ADR 007's how-to) — this is a break-glass fallback only, not day-to-day access."
  type        = string
}

variable "operator_cidr" {
  description = "CIDR allowed to SSH in (port 22). Your own IP/32, not 0.0.0.0/0 — the instance has no other public inbound port, Cloudflare Tunnel handles all app ingress outbound-only (see ADR 011, BFF-proxy pattern applies here too: no public app ports needed on this VM at all)."
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the (public, SSH-only) subnet"
  type        = string
  default     = "10.20.1.0/24"
}

variable "freeform_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    project     = "rastaful-infra-platform"
    environment = "oci-free"
    managed_by  = "terraform"
  }
}
