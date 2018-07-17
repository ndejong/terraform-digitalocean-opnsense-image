# terraform-digitalocean-opnsense-cloud-image
# ============================================================================

# Copyright (c) 2018 Verb Networks Pty Ltd <contact [at] verbnetworks.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# outputs
# ===

output "provider" {
  description = "The compute provider name."
  value = "digitalocean"
}

output "region" {
  description = "The compute provider region identifier."
  value = "${var.digitalocean_region}"
}

output "build_id" {
  description = "The build identifier used to generate this image."
  value = "${random_string.build-id.result}"
}

output "image_name" {
  description = "The image name given to this volume."
  value = "${null_resource.image-name.triggers.string}"
}

output "image_action_outfile" {
  description = "The output file from the image action call to the compute provider."
  value = "${data.null_data_source.image-action-outfile.inputs}"
}
