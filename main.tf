
# terraform-digitalocean-opnsense-cloud-image-builder
# ============================================================================

# Generate a temporary ssh keypair to bootstrap this digitalocean_droplet
# ===

# random-chars used at the tail of digitalocean sshkey name to prevent name collisions
resource "random_string" "random-chars" {
  length = 6
  lower = false
  upper = true
  number = true
  special = false
}

# generate a temporary sshkey to use to bring this instance to life
resource "tls_private_key" "terraform-bootstrap-sshkey" {
  algorithm = "RSA"
  rsa_bits = "4096"
}

# attach this temporary sshkey to the digitalocean user account
# NB: this ssh key remains in CLEAR TEXT in the terraform.tfstate file and can be extracted using something like:-
# $ cat terraform.tfstate | jq --raw-output '.modules[1].resources["tls_private_key.terraform-bootstrap-sshkey"].primary.attributes.private_key_pem'
resource "digitalocean_ssh_key" "terraform-bootstrap-sshkey" {
  name = "terraform-bootstrap-sshkey-${random_string.random-chars.result}"
  public_key = "${tls_private_key.terraform-bootstrap-sshkey.public_key_openssh}"
  depends_on = [ "random_string.random-chars", "tls_private_key.terraform-bootstrap-sshkey" ]
}

# Render the userdata
# ===
data "template_file" "opnsense-config-xml" {
  template = "${file("${path.module}/data/config.xml")}"
  vars {
    opnsense_root_passwd_data = "${bcrypt(var.root_passwd, 10)}"
  }
}

data "template_file" "digitaloceanopnsense-rc-sh" {
  template = "${file("${path.module}/data/digitaloceanopnsense-rc.sh")}"
}

data "template_file" "cloudinit-bootstrap-sh" {
  template = "${file("${path.module}/data/cloudinit-bootstrap.sh")}"
  vars {
    opnsense_release = "18.1"
    opnsense_bootstrap_patch_data = "${base64gzip(file("${path.module}/data/opnsense-bootstrap.patch"))}"
    opnsense_config_data = "${base64gzip(data.template_file.opnsense-config-xml.rendered)}"
    digitaloceanopnsense_rc_data = "${base64gzip(data.template_file.digitaloceanopnsense-rc-sh.rendered)}"
  }
}

# NB: a cloud-init issue prevents gzip+base64 from working, this pipe-chain work-around achieves more-or-less the
# same compact form
data "template_cloudinit_config" "droplet-userdata" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/x-shellscript"
    filename = "cloudinit-bootstrap.sh"
    content = "#!/bin/csh\necho -n '${base64gzip(data.template_file.cloudinit-bootstrap-sh.rendered)}' | b64decode -r | gunzip | /bin/csh"
  }
}

# Establish the digitalocean_droplet
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
  depends_on = [ "digitalocean_ssh_key.terraform-bootstrap-sshkey" ]

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
    ]
  }
}

resource "null_resource" "droplet-removerootsshkeys" {
  count = "${var.remove_root_sshkeys}"

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
