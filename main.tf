# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0

# establish the digitalocean provider
provider "digitalocean" {
  token = "${var.digitalocean_token}"
}

# local test to confirm the digital ocean credentials are valid and that curl is available
# ===
resource "null_resource" "local-tests" {
  provisioner "local-exec" {
    command = <<EOF
        curl -f -s -X GET -H 'Content-Type: application/json' -H 'Authorization: Bearer ${var.digitalocean_token}' \
          'https://api.digitalocean.com/v2/regions' > /dev/null
        if [ $? -gt 0 ]; then
          exit 1
        fi
    EOF
  }
}

# create a unique build-id value for this image build process
# ===
resource "random_string" "build-id" {
  length = 6
  lower = false
  upper = true
  number = true
  special = false

  depends_on = [ "null_resource.local-tests" ]
}

# Generate a temporary ssh keypair to bootstrap this instance
# ===
resource "tls_private_key" "terraform-bootstrap-sshkey" {
  algorithm = "RSA"
  rsa_bits = "4096"

  depends_on = ["null_resource.local-tests"]
}

# attach the temporary sshkey to the provider account for this image build
# ===
# !!!  NB: this ssh key remains in CLEAR TEXT in the terraform.tfstate file and can be extracted using:-
# !!!  $ cat terraform.tfstate | jq --raw-output '.modules[1].resources["tls_private_key.terraform-bootstrap-sshkey"].primary.attributes.private_key_pem'
# ===
resource "digitalocean_ssh_key" "terraform-bootstrap-sshkey" {
  name = "terraform-bootstrap-sshkey-${random_string.build-id.result}"
  public_key = "${tls_private_key.terraform-bootstrap-sshkey.public_key_openssh}"

  depends_on = [ "random_string.build-id", "tls_private_key.terraform-bootstrap-sshkey" ]
}

# FreeBSD uses configinit (not cloud-init) which interprets the user-data based on the first few bytes
# http://www.daemonology.net/blog/2013-12-09-FreeBSD-EC2-configinit.html
# ===
data "template_file" "instance-userdata" {
  template = "#!/bin/sh\necho -n '${base64gzip(file("${path.module}/data/user-data-digitalocean.sh"))}' | b64decode -r | gunzip | /bin/sh"
  vars = { }

  depends_on = ["null_resource.local-tests"]
}

# start this temporary build instance
# ===
resource "digitalocean_droplet" "build-instance" {
  image = "${var.digitalocean_image}"
  name = "${var.hostname}"
  region = "${var.digitalocean_region}"
  size = "${var.digitalocean_size}"
  backups = false     # pointless for this short-lived instance
  monitoring = false  # pointless for this short-lived instance
  ipv6 = "${var.digitalocean_ipv6}"
  private_networking = "${var.digitalocean_private_networking}"
  ssh_keys = [ "${digitalocean_ssh_key.terraform-bootstrap-sshkey.id}" ]

  user_data = "${data.template_file.instance-userdata.rendered}"

  connection {
    type = "ssh"
    user = "root"
    timeout = "600"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      # wait until we get signal that the instance has finished booting
      "while [ ! -e '/var/lib/cloud/instance/boot-finished' ]; do echo '===tail -n3 /var/log/messages==='; tail -n3 /var/log/messages; sleep 3; done",
      "sleep 5"
    ]
  }

  depends_on = [ "digitalocean_ssh_key.terraform-bootstrap-sshkey" ]
}

# render the config.xml with an (optionally different from default: opnsense) root passwd of the image builders choice
# ===
data "template_file" "opnsense-config-xml" {
  template = "${file("${path.module}/data/config-digitalocean.xml")}"
  vars {
    opnsense_root_passwd_data = "${bcrypt(var.root_passwd, 10)}"
  }
}

# render the opnsense-syshook script, which implements the OPNsense <> Cloud-Provider functionality required
# ===
data "template_file" "opnsense-syshook-sh" {
  template = "${file("${path.module}/data/opnsense-syshook-digitalocean.sh")}"
  vars = { }
}

# render the (one time) cloudinit-bootstrap script used to bring this instance to life for the opnsense-bootstrap build
# ===
data "template_file" "opnsense-install-sh" {
  template = "${file("${path.module}/data/opnsense-install.sh")}"
  vars {
    opnsense_release = "${var.opnsense_release}"
    opnsense_config_data = "${base64gzip(data.template_file.opnsense-config-xml.rendered)}"
    opnsense_syshook_data = "${base64gzip(data.template_file.opnsense-syshook-sh.rendered)}"
  }
}

# install opnsense via a remote ssh call
resource "null_resource" "opnsense-install-action" {
  count = "${var.do_opnsense_install}"

  connection {
    host = "${digitalocean_droplet.build-instance.ipv4_address}"
    type = "ssh"
    user = "root"
    timeout = "600"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo -n '${base64gzip(data.template_file.opnsense-install-sh.rendered)}' | b64decode -r | gunzip | /bin/sh",
    ]
  }

  depends_on = [ "digitalocean_droplet.build-instance" ]
}

# do a final cleanup just before the instance does a shutdown-poweroff
# ===
resource "null_resource" "cleanup-shutdown-action" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown}"

  connection {
    host = "${digitalocean_droplet.build-instance.ipv4_address}"
    type = "ssh"
    user = "root"
    timeout = "60"
    agent = false
    private_key = "${tls_private_key.terraform-bootstrap-sshkey.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -Rf /root/.ssh",
      "shutdown -p +20s"
    ]
  }

  depends_on = [ "null_resource.opnsense-install-action" ]
}

# query the DigitalOcean API until this droplet is no longer active
# ===
resource "null_resource" "instance-wait-poweroff" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown}"

  provisioner "local-exec" {
    command = <<EOF
      while [ $(curl -s -X GET -H 'Content-Type: application/json' -H 'Authorization: Bearer ${var.digitalocean_token}' 'https://api.digitalocean.com/v2/droplets/${digitalocean_droplet.build-instance.id}' | jq -r '.droplet.status') = 'active' ]; do
          echo 'Waiting for Droplet ${digitalocean_droplet.build-instance.id} to enter powered off state...'
          sleep 3
      done
    EOF
  }

  depends_on = [ "null_resource.cleanup-shutdown-action" ]
}

# create a name for the droplet - using a null_resource apporach allows us to use a variable in the name here
# ===
resource "null_resource" "image-name" {
  triggers = {
    string = "OPNsense ${var.opnsense_release} - ${timestamp()}"
  }
}

# create the action data for the snaphot we are going to take
# ===
resource "null_resource" "action-data" {
  triggers = {
    json = <<EOF
      {
        "type": "snapshot",
        "name": "${null_resource.image-name.triggers.string}"
      }
    EOF
  }
}

# take a image of this Droplet via the DigitalOcean API
# ===
resource "null_resource" "instance-snapshot-action" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown * var.do_image}"

  provisioner "local-exec" {
    command = <<EOF
      sleep 5
      curl -s -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer ${var.digitalocean_token}' \
        -d '${null_resource.action-data.triggers.json}' \
        'https://api.digitalocean.com/v2/droplets/${digitalocean_droplet.build-instance.id}/actions' \
        > /tmp/opnsense-digitalocean-${random_string.build-id.result}-snapshot-action.json
    EOF
  }

  depends_on = [ "null_resource.instance-wait-poweroff" ]
}

# destroy this droplet to prevent it from running up charges since DigitalOcean Droplets cost money even when powered
# off - note that the Droplet does not disappear from the DigitalOCean management interface until the snapshot image
# process has completed its run
resource "null_resource" "droplet-destroy" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown * var.do_image * var.do_self_destruct}"

  provisioner "local-exec" {
    command = <<EOF
      sleep 10
      curl -s -X DELETE -H 'Content-Type: application/json' -H 'Authorization: Bearer ${var.digitalocean_token}' \
        'https://api.digitalocean.com/v2/droplets/${digitalocean_droplet.build-instance.id}'
    EOF
  }

  depends_on = [ "null_resource.instance-snapshot-action" ]
}

# force some Terraform log output so it is a little easier to immediately observe the final status
# ===
resource "null_resource" "droplet-snapshot-action-status" {
  count = "${var.do_opnsense_install * var.do_cleanup_shutdown * var.do_image}"

  provisioner "local-exec" {
    command = <<EOF
      echo ""
      echo "!!!!"
      echo "OPNsense DigitalOcean image build status: " $(jq -r '.action.status' /tmp/opnsense-digitalocean-${random_string.build-id.result}-snapshot-action.json)
      echo "!!!!"
      echo ""
    EOF
  }
  depends_on = [ "null_resource.instance-snapshot-action" ]
}

