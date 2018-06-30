# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Nicholas de Jong <me@nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# create a unique build-id value for this image build process
# ===
resource "random_string" "build-id" {
  length = 6
  lower = false
  upper = true
  number = true
  special = false
}

# Generate a temporary ssh keypair to bootstrap this digitalocean_droplet
# ===
resource "tls_private_key" "terraform-bootstrap-sshkey" {
  algorithm = "RSA"
  rsa_bits = "4096"
}

# attach the temporary sshkey to the DigitalOcean account
# ===
# !!!  NB: this ssh key remains in CLEAR TEXT in the terraform.tfstate file and can be extracted
# !!!  using a command similar to:-
# !!!  $ cat terraform.tfstate | jq --raw-output '.modules[1].resources["tls_private_key.terraform-bootstrap-sshkey"].primary.attributes.private_key_pem'
# ===
resource "digitalocean_ssh_key" "terraform-bootstrap-sshkey" {
  name = "terraform-bootstrap-sshkey-${random_string.build-id.result}"
  public_key = "${tls_private_key.terraform-bootstrap-sshkey.public_key_openssh}"
  depends_on = [ "random_string.build-id", "tls_private_key.terraform-bootstrap-sshkey" ]
}

# render the config.xml with an (optionally different from default: opnsense) root passwd of the image builders choice
# ===
data "template_file" "opnsense-config-xml" {
  template = "${file("${path.module}/data/config.xml")}"
  vars {
    opnsense_root_passwd_data = "${bcrypt(var.root_passwd, 10)}"
  }
}

# render the opnsensedigitalocean.sh script, which implements the important functionality required
# ===
data "template_file" "opnsensedigitalocean-sh" {
  template = "${file("${path.module}/data/opnsensedigitalocean.sh")}"
}

# render the (one time) cloudinit-bootstrap script used to bring this droplet to life for the opnsense-bootstrap build
# ===
data "template_file" "cloudinit-bootstrap-sh" {
  template = "${file("${path.module}/data/cloudinit-bootstrap.sh")}"
  vars {
    opnsense_release = "${var.opnsense_release}"
    opnsense_bootstrap_patch_data = "${base64gzip(file("${path.module}/data/opnsense-bootstrap.patch"))}"
    opnsense_config_data = "${base64gzip(data.template_file.opnsense-config-xml.rendered)}"
    opnsensedigitalocean_rc_data = "${base64gzip(data.template_file.opnsensedigitalocean-sh.rendered)}"
  }
}

# render the actual cloud-init data that the Droplet will use to unroll the sub-scripts above - unfortunately
# though the cloud-init tooling on FreeBSD prevents native gzip+base64 from working, so we have to pipe-chain
# a work-around to achieve more-or-less the same compact form
# ===
data "template_cloudinit_config" "droplet-userdata" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/x-shellscript"
    filename = "cloudinit-bootstrap.sh"
    content = "#!/bin/sh\necho -n '${base64gzip(data.template_file.cloudinit-bootstrap-sh.rendered)}' | b64decode -r | gunzip | /bin/sh"
  }
}

# establish the digitalocean_droplet that will be used to generate an image from
# ===
resource "digitalocean_droplet" "droplet" {
  image = "${var.digitalocean_image}"
  name = "${var.hostname}"
  region = "${var.digitalocean_region}"
  size = "${var.digitalocean_size}"
  backups = "${var.digitalocean_backups}"
  monitoring = "${var.digitalocean_monitoring}"
  ipv6 = "${var.digitalocean_ipv6}"
  private_networking = "${var.digitalocean_private_networking}"
  ssh_keys = [ "${digitalocean_ssh_key.terraform-bootstrap-sshkey.id}" ]

  user_data = "${data.template_cloudinit_config.droplet-userdata.rendered}"

  connection {
    type = "ssh"
    user = "root"
    timeout = "900"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -e '/var/lib/cloud/instance/boot-finished' ]; do echo '===tail -n3 /var/log/messages==='; tail -n3 /var/log/messages; sleep 3; done",
      "shutdown -p +20s"
    ]
  }

  depends_on = [ "digitalocean_ssh_key.terraform-bootstrap-sshkey" ]
}

# do a final cleanup just before the droplet does a shutdown-poweroff
# ===
resource "null_resource" "droplet-final-cleanup" {
  count = "1"

  connection {
    host = "${digitalocean_droplet.droplet.ipv4_address}"
    type = "ssh"
    user = "root"
    timeout = "60"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -Rf /root/.ssh/authorized_keys",
      "rm -Rf /root/.ssh/*.pub",
      #"sed -i -e '/^PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config",
      #"service sshd reload"
    ]
  }

  depends_on = [ "digitalocean_droplet.droplet" ]
}

# query the DigitalOcean API until this droplet is no longer active
# ===
resource "null_resource" "droplet-wait-poweroff" {
  provisioner "local-exec" {
    command = <<EOF
        while [ $(curl -s -X GET -H 'Content-Type: application/json' -H 'Authorization: Bearer ${var.digitalocean_token}' 'https://api.digitalocean.com/v2/droplets/${digitalocean_droplet.droplet.id}' | jq -r '.droplet.status') = 'active' ]; do
            echo 'Waiting for Droplet ${digitalocean_droplet.droplet.id} to enter powered off state...'
            sleep 3
        done
    EOF
  }
  depends_on = [ "null_resource.droplet-final-cleanup" ]
}

# create a name for the droplet - using a null_resource apporach allows us to use a variable in the name here
# ===
resource "null_resource" "image_name" {
    triggers = {
        string = "OPNsense ${var.opnsense_release} - ${timestamp()}"
    }
}

# create the action data for the snaphot we are going to take
# ===
resource "null_resource" "action_data" {
    triggers = {
        json = <<EOF
          {
            "type": "snapshot",
            "name": "${null_resource.image_name.triggers.string}"
          }
        EOF
    }
}

# take a image of this Droplet via the DigitalOcean API
# ===
resource "null_resource" "droplet-snapshot-action" {
  provisioner "local-exec" {
    command = <<EOF
        curl -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer ${var.digitalocean_token}' \
          -d '${null_resource.action_data.triggers.json}' \
          'https://api.digitalocean.com/v2/droplets/${digitalocean_droplet.droplet.id}/actions' \
          > /tmp/opnsense-digitalocean-${random_string.build-id.result}-snapshot-action.json
    EOF
  }
  depends_on = [ "null_resource.droplet-wait-poweroff" ]
}

# destroy this droplet to prevent it from running up charges since DigitalOcean Droplets cost money even when powered
# off - note that the Droplet does not disappear from the DigitalOCean management interface until the snapshot image
# process has completed its run
resource "null_resource" "droplet-destroy" {
  count = 1

  provisioner "local-exec" {
    command = <<EOF
        curl -s -X DELETE -H 'Content-Type: application/json' -H 'Authorization: Bearer ${var.digitalocean_token}' \
          'https://api.digitalocean.com/v2/droplets/${digitalocean_droplet.droplet.id}'
    EOF
  }
  depends_on = [ "null_resource.droplet-snapshot-action" ]
}

# force some Terraform log output so it is a little easier to immediately observe the final status
# ===
resource "null_resource" "droplet-snapshot-action-status" {
  provisioner "local-exec" {
    command = <<EOF
      echo ""
      echo "!!!!"
      echo "OPNsense DigitalOcean image build status: " $(jq -r '.action.status' /tmp/opnsense-digitalocean-${random_string.build-id.result}-snapshot-action.json)
      echo "!!!!"
      echo ""
    EOF
  }
  depends_on = [ "null_resource.droplet-snapshot-action" ]
}

