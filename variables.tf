# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# required variables - no defaults
# ===

variable "digitalocean_region" {
  description = "The DigitalOcean region-slug to start this digitalocean-droplet within (nyc1, sgp1, lon1, nyc3, ams3, fra1, tor1, sfo2, blr1)"
}

variable "digitalocean_token" {
  description = "Your DigitalOcean API token used to issue cURL API calls directly to DigitalOcean to create the required image"
}

variable "opnsense_release" {
  description = "The OPNsense release to target for this image build"
}

# variables - with defined defaults
# ===

variable "root_passwd" {
  description = "The initial root password for OPNsense once the image is built."
  default = "opnsense"
}

variable "hostname" {
  description = "The hostname applied to this digitalocean-droplet within the image build process only."
  default = "opnsense-cloud-image-builder"
}

variable "digitalocean_image" {
  description = "The DigitalOcean image to use as the base for this digitalocean-droplet."
  default = "freebsd-11-1-x64"
}

variable "digitalocean_size" {
  description = "The size to use for this digitalocean-droplet."
  default = "s-1vcpu-1gb"
}

variable "digitalocean_ipv6" {
  description = "Enable/disable getting a public IPv6 on this digitalocean-droplet."
  default = true
}

variable "digitalocean_private_networking" {
  description = "Enable/disable private-networking functionality on this digitalocean-droplet."
  default = true
}

variable "do_opnsense_install" {
  description = "Cause OPNsense to be installed once the instance is reachable."
  default = 1
}

variable "do_cleanup_shutdown" {
  description = "Cause the system to perform cleanup operations and then shutdown."
  default = 1
}

variable "do_image" {
  description = "Cause a Digital Ocean Droplet image to be taken of the Droplet while powered off."
  default = 1
}

variable "do_self_destruct" {
  description = "Cause the Droplet that was used to create the snapshot image to delete itself itself once the image is done."
  default = 1
}
