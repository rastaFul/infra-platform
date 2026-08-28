output "instance_id" {
  value = oci_core_instance.this.id
}

output "instance_public_ip" {
  value = oci_core_instance.this.public_ip
}

output "instance_display_name" {
  value = oci_core_instance.this.display_name
}

output "vcn_id" {
  value = oci_core_vcn.this.id
}
