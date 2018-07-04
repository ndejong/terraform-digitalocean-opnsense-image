# Terraform + Digital Ocean + OPNsense :: Image Builder

Terraform module to create a Digital Ocean Droplet snapshot-image that can subsequently be used to start 
an OPNsense instance within Digital Ocean.
 * [OPNsense](https://www.opnsense.org/)
 * [Digital Ocean](https://www.digitalocean.com/)

Of particular note is the support for the Digital Ocean (OpenStack based) approach to providing Droplets 
their seed data, including public-IPv4, public-IPv6, private-IPv4, root-sshkey and user-data which is all
be parsed and injected into the OPNsense `/conf/config.xml` file at Droplet boot.  This allows the resulting 
OPNsense image to be used in Terraform devops automation situations.

Users of the resulting OPNsense image may additionally wish to implement user_data that fetches an external
`confg.xml` file and places it in the usual `/conf/config.xml` location, which will be loaded at startup.

```bash
#!/bin/sh
fetch -o "/conf/config.xml" "https://your-awesome-hosting/opnsense-backups/latest.xml"
```


## Usage
This module is mildly unusual in that the final result does **not** provide a running Droplet.  The correct behaviour
of this module will result in a Digital Ocean Droplet image while the Droplet used in the process of creating the 
image will self destruct.  The self destruct behaviour can be optionally disabled by toggling the `self_destruct` 
variable which can be useful in situations that require debugging.

The example below shows an example setup - note that the **root_passwd** variable is optional and by default will
use the same default password that OPNsense uses, that is "opnsense" - be smart, change this as your OPNsense 
instance will be publicly accessible to begin with.

```hcl
variable "do_token" {}

module "opnsense-cloud-image-builder" {
  source  = "ndejong/opnsense-cloud-image-builder/digitalocean"

  digitalocean_region = "sgp1"
  digitalocean_token = "${var.do_token}"
  opnsense_release = "18.1"

  root_passwd = "honeyPot.."
}

output "image_name" { value = "${module.opnsense-cloud-image-builder.image_name}"}
output "action_status" { value = "${module.opnsense-cloud-image-builder.action_status}"}
```

The user should perform a `terraform destroy` once complete to remove the resources that have allocated in the local 
`tfstate` - they can all safely be destroyed, your new Droplet image will not be removed in this destroy action.


## Warning!
The default rules used in this arrangement differ from the default OPNsense rules in that they **allow** access to the 
OPNsense control interfaces via TCP22 (SSH) and TCP443 (HTTPS) to facilitate your initial connection(s) to the 
system for setup etc.

Leaving the system in this arrangement is **NOT** recommended and you should take steps to restrict the source 
addresses that can connect to your OPNsense control interfaces.


## Notes and Observations
 * The image "build" process leverages the OPNsense provided `opnsense-bootstrap.sh` tool to "convert" a FreeBSD 
   Droplet into an OPNsense one, check it out here - https://github.com/opnsense/update
 * Builds generally take around 10 minutes when using a small-sized Digital Ocean Droplet size - you will see a lot
   of Terraform output as the process continues.
 * Builds can fail for many reasons, external packages may not download, kernel-panics have been observed, you do need
   to keep an eye on the Terraform logging output to make sure nothing obvious is going wrong. 
 * The Digital Ocean API can act mysteriously at times,  several times it has been observed that the final Droplet
   image process silents fails to register the new Droplet snapshot, the resolution seems to be just `destroying`
   and going through the process again without changing anything.
 * Remember to issue the `terraform destroy` at the end, else you may become confused what state you are in the next
   time to come to roll another Droplet based OPNsense image.

## Builds Tested
 * digitalocean-slug: `freebsd-11-1-x64` > OPNsense 18.1.10 (@ 2018-07-04T15:39:47Z)
 * digitalocean-slug: `freebsd-11-1-x64` > OPNsense 18.1.11 (@ 2018-06-30T15:11:37Z)

## Input Variables - Required

### digitalocean_region
The DigitalOcean region-slug to start this digitalocean-droplet within (nyc1, sgp1, lon1, nyc3, ams3, fra1, tor1, sfo2, blr1)

### digitalocean_token
Your DigitalOcean API token used to issue cURL API calls directly to DigitalOcean to create the required image

### opnsense_release
The OPNsense release to target for this image build


## Input Variables - Optional

### root_passwd
The initial root password for OPNsense once the image is built.
* default = "opnsense"


### hostname
The hostname applied to this digitalocean-droplet within the image build process only.
* default = "opnsense-cloud-image-builder"

### self_destruct
Cause the Droplet used to create the snapshot image to self destruct itself once complete.
* default = 1

### digitalocean_image
The DigitalOcean image to use as the base for this digitalocean-droplet.
* default = "freebsd-11-1-x64"

### digitalocean_size
The size to use for this digitalocean-droplet.
* default = "s-1vcpu-1gb"

### digitalocean_backups
Enable/disable backup functionality on this digitalocean-droplet - untested with OPNsense
* default = false

### digitalocean_monitoring
Enable/disable monitoring functionality on this digitalocean-droplet - untested with OPNsense
* default = false

### digitalocean_ipv6
Enable/disable getting a public IPv6 on this digitalocean-droplet.
* default = true

### digitalocean_private_networking
Enable/disable private-networking functionality on this digitalocean-droplet.
* default = true


## Outputs

### region
The DigitalOcean region-slug this digitalocean-droplet is running in.

### image_name
The image name used for this Droplet image.

### action_status
The Droplet image action response data received from the DigitalOcean API.


## Authors
Module managed by [Nicholas de Jong](https://github.com/ndejong).

## License
Apache 2 Licensed. See LICENSE file for full details.
