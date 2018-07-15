# Image Create :: OPNsense on Digital Ocean

Terraform module to create a Digital Ocean Droplet snapshot-image that can subsequently be used to start an OPNsense 
instance within Digital Ocean.
 * [OPNsense](https://www.opnsense.org/)
 * [Digital Ocean](https://www.digitalocean.com/)

Of particular note is the support for the Digital Ocean (OpenStack based) approach to providing Droplets their seed 
data, including public-IPv4, public-IPv6, private-IPv4, root-sshkey and user-data which is all be parsed and injected 
into the OPNsense `/conf/config.xml` file at Droplet boot.  This allows the resulting OPNsense image to be used in 
Terraform devops automation situations.

Users of the resulting OPNsense can additionally inject standard `user-data` scripts at initial instance boot.


## Usage
This module is mildly unusual in that the final result does **not** provide a running Droplet.  The correct behaviour
of this module will result in a Digital Ocean Droplet image while the Droplet used in the process of creating the image 
will self destruct.

The example below shows an example setup - note that the **root_passwd** variable is optional and by default will
use the same default password that OPNsense uses, that is "opnsense" - be smart, change this as your OPNsense instance 
will be **publicly** accessible to begin with unless you take other measures to prevent inbound access to TCP22 (SSH) 
and TCP443 (HTTPS).

```hcl
variable "do_token" {}

module "opnsense-cloud-image-builder" {
  source  = "verbnetworks/opnsense-image/digitalocean"

  opnsense_release = "18.1"
  root_passwd = "honeyPot..."

  digitalocean_region = "sgp1"
  digitalocean_token = "${var.do_token}"


  do_opnsense_install = 1
  do_cleanup_shutdown = 1
  do_image = 1
  do_self_destruct = 1
}

output "image_name" { value = "${module.opnsense-cloud-image-builder.image_name}"}
output "action_status" { value = "${module.opnsense-cloud-image-builder.action_status}"}
```

The user should perform a `terraform destroy` once complete to remove the resources that have allocated in the local 
`tfstate` - they can all safely be destroyed, the new Droplet image will not be removed in this destroy action because
the action to create the image is performed as a `local-exec` call to `curl` thus preventing it from being a Terraform
resource.


## Warning!
The default rules used in this arrangement differ from the default OPNsense rules in that they **allow** access to the 
OPNsense control interfaces via TCP22 (SSH) and TCP443 (HTTPS) to facilitate your initial connection(s) to the 
system for setup etc.

Leaving the system in this arrangement is **NOT** recommended and you should take steps to restrict the source 
addresses that can connect to your OPNsense control interfaces.


## Notes and Observations
 * The image "build" process leverages the OPNsense provided `opnsense-bootstrap.sh` tool to "convert" a FreeBSD 
   Droplet into an OPNsense one, check it out here - [https://github.com/opnsense/update](https://github.com/opnsense/update)
 * Builds generally take around 10 minutes when using a small-sized Digital Ocean Droplet size, you will see a lot of 
   Terraform output as the build process continues.
 * Builds can fail for many reasons, external packages may not download, kernel-panics have been observed, you do need
   to keep an eye on the Terraform logging output to make sure nothing obvious is going wrong. 
 * The Digital Ocean API can act mysteriously at times,  several times it has been observed that the final Droplet
   image process silents fails to register the new Droplet snapshot, the resolution seems to be just `destroying`
   and going through the process again without changing anything.
 * Remember to issue the `terraform destroy` at the end, else you may become confused what state you are in the next
   time to come to roll another Droplet based OPNsense image.


## Builds Tested
 * (v0.2) digitalocean-slug: **freebsd-11-1-x64** > **OPNsense 18.1.10** (@ 2018-07-04T15:39:47Z)
 * (v0.2) digitalocean-slug: **freebsd-11-1-x64** > **OPNsense 18.1.11** (@ 2018-06-30T15:11:37Z)
 * (v0.3) digitalocean-slug: **freebsd-11-2-x64** > **OPNsense 18.1.11** (@ 2018-07-06T17:31:52Z)


## What about Packer?
Packer, also produced by Hashicorp is an awesome tool, but requires learning yet another tool-chain. Since the resulting 
Digital Ocean images are targeted at DevOps people that use Terraform, it just felt more natural to do the whole build
process in Terraform.


## History
This module was originally published at `https://github.com/ndejong/terraform-digitalocean-opnsense-cloud-image-builder` 
and was subsequently moved which required it to be removed and re-added to the Terraform Module repository.

****

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
Module managed by [Verb Networks](https://github.com/verbnetworks).

## License
Apache 2 Licensed. See LICENSE file for full details.
