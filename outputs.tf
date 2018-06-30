
# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# outputs
# ===

output "region" {
  description = "The DigitalOcean region-slug this digitalocean-droplet is running in."
  value = "${var.digitalocean_region}"
}

output "image_name" {
  description = "The image name used for this Droplet image."
  value = "${null_resource.image_name.triggers.string}"
}

output "action_status" {
  description = "The Droplet image action response data received from the DigitalOcean API."
  value = "/tmp/opnsense-digitalocean-${random_string.build-id.result}-snapshot-action.json"
}

