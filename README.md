# Image Create :: OPNsense on Digital Ocean

Terraform module to create a Digital Ocean Droplet snapshot-image that can subsequently be used to start an OPNsense 
instance within Digital Ocean.
 * [OPNsense](https://www.opnsense.org/)
 * [Digital Ocean](https://www.digitalocean.com/)

This module provides an boot-time syshook for OPNsense that collects input parameters from the Digital Ocean (Open 
Stack based) meta-data and applies them to the OPNsense `config.xml` file at boot.  Config attributes that are
managed this way include:-
 - root user sshkey
 - Public and Private network interface cards
 - IPv4 address, subnet, gateway, dns
 - IPv6 address, subnet, gateway 

This allows the resulting OPNsense Droplet Image to be used in regular Terraform devops automation situations.  Additionally, 
users of the resulting OPNsense instance can inject `user-data` scripts at initial instance boot, however the system
does not include cloudinit, so `user-data` scripts need to be contained `/bin/sh` scripts. 


## Usage
This module is mildly unusual in that the final result does **not** provide a running Droplet.  The correct behaviour
of this module will result in a Digital Ocean Droplet image while the Droplet used in the process of creating the image 
will self destruct.

The example below shows an example setup - note that the **root_passwd** variable is optional and by default will
use the same default password that OPNsense uses, that is "opnsense" - be smart, change this because your OPNsense 
instance will be **publicly** accessible to begin with unless you take other measures to prevent inbound access to 
TCP22 (SSH) and TCP443 (HTTPS).

```hcl
variable "do_token" {}    # NB: set via env value, TF_VAR_do_token

module "opnsense-image" {
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

output "provider" { value = "${module.opnsense-image.provider}"}
output "region" { value = "${module.opnsense-image.region}"}
output "build_id" { value = "${module.opnsense-image.build_id}"}
output "image_name" { value = "${module.opnsense-image.image_name}"}
output "image_action_outfile" { value = "${module.opnsense-image.image_action_outfile}"}
```

After the build process completes you should observe among the final Terraform log lines the following, thus indicating 
the build process is complete and the image is taking place on the Digital Ocean backend.
```text
action-status (local-exec): !!!!
action-status (local-exec): !!!! build_id: YDYAKA
action-status (local-exec): !!!! image_name: OPNsense 18.1 - 20180717Z102528
action-status (local-exec): !!!! image_action_outfile: /tmp/opnsense-YDYAKA-image-action.json
action-status (local-exec): !!!!
action-status (local-exec): !!!! Remember to terraform destroy resources once image action is complete
action-status (local-exec): !!!!
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
 * Builds generally take around 10 minutes when using a small-sized Digital Ocean Droplet size.
 * You will see a **lot** of Terraform log output as the build process continues, keep in mind that builds can fail for 
   many surprising reasons, external packages may not download and kernel-panics have been observed, so it is worth
   keeping an eye on the Terraform logging output to make sure nothing really obvious is going wrong. 
 * The Digital Ocean API can act mysteriously at times,  several times it has been observed that the final Droplet
   image process silents fails to register the new Droplet snapshot, the resolution seems to be just `destroying`
   and going through the process again without changing anything.
 * Remember to issue the `terraform destroy` at the end, else you may become confused what state you are in the next
   time to come to roll another Droplet based OPNsense image.


## What about Packer?
Packer, also produced by Hashicorp is an awesome tool, but requires learning yet another tool-chain. Since the resulting 
Digital Ocean images are targeted at DevOps people that use Terraform, it just felt more natural to do the whole build
process in Terraform.


## History
This module was originally published via `github.com/ndejong/terraform-digitalocean-opnsense-cloud-image-builder` and was 
subsequently moved which required it to be removed and re-added within the Terraform Module repository.


## Builds Confirmed
 * (v0.2.0) digitalocean-slug: **freebsd-11-1-x64** > **OPNsense 18.1.10** (@ 2018-07-04T15:39:47Z)
 * (v0.2.0) digitalocean-slug: **freebsd-11-1-x64** > **OPNsense 18.1.11** (@ 2018-06-30T15:11:37Z)
 * (v0.3.0) digitalocean-slug: **freebsd-11-2-x64** > **OPNsense 18.1.11** (@ 2018-07-06T17:31:52Z)
 * (v0.3.0) digitalocean-slug: **freebsd-11-2-x64** > **OPNsense 18.1.12** (@ 2018-07-17T09:09:00Z)

NB: as at 2018-07-17 OPNSense 18.7 has not yet been confirmed to correctly build, this will be resolved once OPNSense
officially announce this build.


## Compute Providers Supported
 * [Amazon Web Services](https://github.com/verbnetworks/terraform-digitalocean-aws-image)
 * [Digital Ocean](https://github.com/verbnetworks/terraform-digitalocean-opnsense-image)


****


## Input Variables - Required

### opnsense_release
The OPNsense release to target for this image build

### digitalocean_region
The DigitalOcean region-slug to start this digitalocean-droplet within (nyc1, sgp1, lon1, nyc3, ams3, fra1, tor1, sfo2, blr1)

### digitalocean_token
Your DigitalOcean API token used to issue cURL API calls directly to DigitalOcean to create the required image


## Input Variables - Optional

### root_passwd
The initial root password for OPNsense once the image is built.
* default = "opnsense"

### hostname
The hostname applied to this digitalocean-droplet within the image build process only.
* default = "opnsense-image"

### digitalocean_image
The DigitalOcean image to use as the base for this digitalocean-droplet.
* default = "freebsd-11-1-x64"

### digitalocean_size
The size to use for this digitalocean-droplet.
* default = "s-1vcpu-1gb"

### digitalocean_ipv6
Enable/disable getting a public IPv6 on this digitalocean-droplet.
* default = true

### digitalocean_private_networking
Enable/disable private-networking functionality on this digitalocean-droplet.
* default = true

### do_opnsense_install
Cause OPNsense to be installed once the instance is reachable.
 - default = 1

### do_cleanup_shutdown
Cause the system to perform cleanup operations and then shutdown.
 - default = 1

### do_image
Cause a Digital Ocean Droplet image to be taken of the Droplet while powered off.
 - default = 1

### do_self_destruct
Cause the Droplet that was used to create the snapshot image to delete itself itself once the image is done.
 - default = 1


## Outputs

### provider
The compute provider name.

### region
The compute provider region identifier.

### build_id
The build identifier used to generate this image.

### image_name
The image name given to this volume.

### image_action_outfile
The output file from the image action call to the compute provider.


****


## Authors
Module managed by [Verb Networks](https://github.com/verbnetworks).

## License
Apache 2 Licensed. See LICENSE file for full details.
