# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Nicholas de Jong <contact[@]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# outputs
# ===

output "region" {
  description = "The DigitalOcean region-slug this digitalocean-droplet is running in."
  value = "${var.digitalocean_region}"
}

output "image_name" {
  description = "The image name used for this Droplet image."
  value = "${null_resource.image-name.triggers.string}"
}

output "action_status" {
  description = "The Droplet image action response data received from the DigitalOcean API."
  value = "/tmp/opnsense-digitalocean-${random_string.build-id.result}-snapshot-action.json"
}

