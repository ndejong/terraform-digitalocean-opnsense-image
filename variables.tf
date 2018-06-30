
# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

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

variable "hostname" {
  description = "The hostname applied to this digitalocean-droplet."
  default = "opnsense-cloud-image-builder"
}

variable "root_passwd" {
  description = "The initial root password for OPNsense once installed."
  default = "opnsense"
}

variable "digitalocean_image" {
  description = "The DigitalOcean image to use as the base for this digitalocean-droplet."
  default = "freebsd-11-1-x64"
}

variable "digitalocean_size" {
  description = "The size to use for this digitalocean-droplet."
  default = "s-1vcpu-1gb"
}

variable "digitalocean_backups" {
  description = "Enable/disable backup functionality on this digitalocean-droplet."
  default = false
}

variable "digitalocean_monitoring" {
  description = "Enable/disable monitoring functionality on this digitalocean-droplet."
  default = false
}

variable "digitalocean_ipv6" {
  description = "Enable/disable getting a public IPv6 on this digitalocean-droplet."
  default = true
}

variable "digitalocean_private_networking" {
  description = "Enable/disable private-networking functionality on this digitalocean-droplet."
  default = true
}
