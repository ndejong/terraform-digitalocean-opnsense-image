#!/bin/sh

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0

# Cause the instance to allow root sshkey based console access for this build
mkdir -p /root/.ssh
echo "$(jq -r -M '.public_keys[0]' '/var/lib/cloud/seed/config_drive/digitalocean_meta_data.json')" > /root/.ssh/authorized_keys

chown -R root /root/.ssh
chmod 700 /root/.ssh
chmod 600 /root/.ssh/*

sed -i -e '/.*PasswordAuthentication/s/^.*$/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -e '/.*PubkeyAuthentication/s/^.*$/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i -e '/.*PermitRootLogin/s/^.*$/PermitRootLogin yes/' /etc/ssh/sshd_config

service sshd reload

# that's all to do here
exit 0
