#!/bin/csh

# Set some required resource source locations
set opnsense_bootstrap_uri='https://raw.githubusercontent.com/opnsense/update/${opnsense_release}/bootstrap/opnsense-bootstrap.sh'
set oniguruma_pkg_uri="https://pkg.freebsd.org/FreeBSD:11:`uname -m`/release_2/All/oniguruma-6.8.1.txz"
set jq_pkg_uri="https://pkg.freebsd.org/FreeBSD:11:`uname -m`/release_2/All/jq-1.5_3.txz"

# install recent certificate root authority certs so we can more-safely fetch from the bootstrap source
pkg install -y ca_root_nss

# fetch the OPNsense bootstrap script
fetch -o /tmp/opnsense-bootstrap.sh "$opnsense_bootstrap_uri"

# patch the OPNsense bootstrap script to suit our install requirement
echo -n '${opnsense_bootstrap_patch_data}' | b64decode -r | gunzip > /tmp/opnsense-bootstrap.patch
patch /tmp/opnsense-bootstrap.sh /tmp/opnsense-bootstrap.patch
chmod 755 /tmp/opnsense-bootstrap.sh

# call the patched OPNsense bootstrap script
/tmp/opnsense-bootstrap.sh -y

# Add these FreeBSD packages manually rather than enabling the full FreeBSD repo here /usr/local/etc/pkg/repos/FreeBSD.conf
fetch -o /tmp/oniguruma.txz "$oniguruma_pkg_uri"
fetch -o /tmp/jq.txz "$jq_pkg_uri"
pkg-static add /tmp/oniguruma.txz
pkg-static add /tmp/jq.txz

# Replace the alternate initial config.xml from $path.module/data/config.xml
echo -n '${opnsense_config_data}' | b64decode -r | gunzip > /usr/local/etc/config.xml

# Install our a digitaloceanopnsense rc.d script to deal with getting Digital Ocean IP address configuration into OPNsense
echo 'digitaloceanopnsense_enable="YES"' > /etc/rc.conf.d/digitaloceanopnsense
echo -n '${digitaloceanopnsense_rc_data}' | b64decode -r | gunzip > /usr/local/etc/rc.d/digitaloceanopnsense
chmod 755 /usr/local/etc/rc.d/digitaloceanopnsense

# Remove things that do not belong under OPNsense and that we will not want in an image
#rm -Rf /var/lib/cloud
rm -Rf /var/log/*
rm -Rf /usr/home/freebsd/.ssh
rm -f /etc/rc.conf
touch /etc/rc.conf
rm -f /usr/local/etc/rc.d/digitalocean
rm -f /usr/local/etc/rc.d/digitaloceanpre

# finally, reboot after 30 seconds delay
echo "!! REBOOT DUE IN 30 SECONDS !!"
shutdown -r +30s &

exit 0
