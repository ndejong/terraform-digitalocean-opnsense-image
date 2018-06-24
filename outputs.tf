
# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# outputs
# ===

output "hostname" {
  description = "The hostname applied to this digitalocean-droplet."
  value = "${var.hostname}"
}

output "region" {
  description = "The digitalocean region-slug this digitalocean-droplet is running in."
  value = "${var.digitalocean_region}"
}

output "ipv4_address" {
  description = "The public IPv4 address of this digitalocean-droplet."
  value = "${digitalocean_droplet.droplet.ipv4_address}"
}

output "terraform_bootstrap_sshkey" {
  description = "The terraform-bootstrap-sshkey that was used to bootstrap this droplet."
  value = "terraform-bootstrap-sshkey-${random_string.random-chars.result}"
}
