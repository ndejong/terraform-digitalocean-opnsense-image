#!/bin/sh

# Copyright (c) 2018 Nicholas de Jong <contact[at]nicholasdejong.com>
#  - All rights reserved.
#
# Apache License v2.0
#  - http://www.apache.org/licenses/LICENSE-2.0


# configuration
CONFIGFILE='/conf/config.xml'


# make sure required binaries are available on this system first
if [ $(which jq | wc -l | tr -d ' ') -lt 1 ]; then
    echo 'FATAL: missing required binary, "jq" - install "jq" package before using this tool'
    exit 1
fi

if [ $(which xml | wc -l | tr -d ' ') -lt 1 ]; then
    echo 'FATAL: missing required binary, "xml" - install "xmlstarlet" package before using this tool'
    exit 1
fi


opnsense_ipv4masktosubnet()
{
    case $1 in

        "255.255.0.0")
            subnet=16
            ;;
        "255.255.128.0")
            subnet=17
            ;;
        "255.255.192.0")
            subnet=18
            ;;
        "255.255.224.0")
            subnet=19
            ;;
        "255.255.240.0")
            subnet=20
            ;;
        "255.255.248.0")
            subnet=21
            ;;
        "255.255.252.0")
            subnet=22
            ;;
        "255.255.254.0")
            subnet=23
            ;;
        "255.255.255.0")
            subnet=24
            ;;
        "255.255.255.128")
            subnet=25
            ;;
        "255.255.255.192")
            subnet=26
            ;;
        "255.255.255.224")
            subnet=27
            ;;
        "255.255.255.240")
            subnet=28
            ;;
        "255.255.255.248")
            subnet=29
            ;;
        "255.255.255.252")
            subnet=30
            ;;
        *)
            subnet=32
            ;;
    esac
    echo $subnet
}

opnsense_config()
{
    configfile="$CONFIGFILE"
    tempfile="/tmp/config-xmlstarlet-edit-`date -u +%Y%m%dZ%H%M%S`-`head /dev/urandom | md5 | head -c4`.tmp"

    method="$1"
    xpath="$2"
    value="$3"

    # create
    if [ $method == "create" ]; then
        name=$(echo "$xpath" | rev | cut -f1 -d'/' | rev)
        xpath_sub=$(echo "$xpath" | rev | cut -f2- -d'/' | rev)
        xml ed -P -s "$xpath_sub" -t "elem" -n "$name" -v "$value" "$configfile" > "$tempfile"
        if [ $(xml sel -t -v "$xpath" "$tempfile" | tail -n1) == "$value" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # read
    elif [ $method == "read" ]; then
        echo "$(xml sel -t -v "$xpath" "$configfile")"
        return 0

    # update
    elif [ $method == "update" ]; then
        xml ed -P -u "$xpath" -v "$value" "$configfile" > "$tempfile"
        if [ $(xml sel -t -v "$xpath" "$tempfile") == "$value" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # delete
    elif [ $method == "delete" ]; then
        xml ed -P -d "$xpath" "$configfile" > "$tempfile"
        if [ -z $(xml sel -t -v "$xpath" "$tempfile") ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # upsert (naive, no locking)
    elif [ $method == "upsert" ]; then
        # update (up-)
        if [ ! -z $(xml sel -t -v "$xpath" "$configfile") ]; then
            xml ed -P -u "$xpath" -v "$value" "$configfile" > "$tempfile"
            if [ $(xml sel -t -v "$xpath" "$tempfile") == "$value" ]; then
                mv "$tempfile" "$configfile"
                return 0
            fi
        # create (-sert)
        else
            name=$(echo "$xpath" | rev | cut -f1 -d'/' | rev)
            xpath_sub=$(echo "$xpath" | rev | cut -f2- -d'/' | rev)
            xml ed -P -s "$xpath_sub" -t "elem" -n "$name" -v "$value" "$configfile" > "$tempfile"
            if [ $(xml sel -t -v "$xpath" "$tempfile") == "$value" ]; then
                mv "$tempfile" "$configfile"
                return 0
            fi
        fi
    fi

    return 1
}

opnsense_main()
{
        # =====================================================================

        meta="/var/lib/cloud/seed/config_drive/digitalocean_meta_data.json"

        # Mount the Digital Ocean config_drive if not already
        if [ $(mount | grep '/dev/vtbd1' | wc -l | tr -d ' ') -lt 1 ]; then
            echo "OPNsense Syshook: mount config_drive"
            mkdir -p /var/lib/cloud/seed/config_drive
            mount_cd9660  -o ro -v /dev/vtbd1 /var/lib/cloud/seed/config_drive \
                || echo "OPNsense Syshook: failed to mount config drive"
        else
            echo "OPNsense Syshook: config_drive already mounted"
        fi

        # =====================================================================

        # instance user_data
        user_data=$(jq -r -M '.user_data' $meta)

        # pull in the instance user_data and run only at the first boot
        if [ ! -z "$user_data" ] && [ ! -f "/var/lib/cloud/instance/user-data.sh" ]; then
            mkdir -p /var/lib/cloud/instance
            echo -n "$user_data" > /var/lib/cloud/instance/user-data.sh
            if [ $(cat /var/lib/cloud/instance/user-data.sh | wc -c | tr -d ' ') -gt 0 ]; then
                chmod 700 /var/lib/cloud/instance/user-data.sh
                echo "OPNsense Syshook: /var/lib/cloud/instance/user-data.sh starting"
                /var/lib/cloud/instance/user-data.sh
                echo "OPNsense Syshook: /var/lib/cloud/instance/user-data.sh finished"
            fi
        fi

        # =====================================================================

        echo "OPNsense Syshook: acquiring instance configuration attributes"

        # root_sshkey_data - NB: must be base64 encoded
        root_sshkey_data=$(jq -r -M '.public_keys[0]' $meta | b64encode -r - | tr -d '\n')

        # interfaces
        public_interface=$(opnsense_config read "//interfaces/public/if")
        private_interface=$(opnsense_config read "//interfaces/private/if")

        # mac addresses
        public_interface_mac=$(ifconfig $public_interface | grep hwaddr | cut -d' ' -f2)
        private_interface_mac=$(ifconfig $private_interface | grep hwaddr | cut -d' ' -f2)

        # public_interface
        if [ ! -z $public_interface_mac ]; then
            # public.ipv4.ip_address
            public_ip4_addr=$(jq -r -M '.interfaces.public[0].ipv4.ip_address' $meta)
            public_ip4_subnet=$(opnsense_ipv4masktosubnet $(jq -r -M '.interfaces.public[0].ipv4.netmask' $meta))
            public_ip4_gateway=$(jq -r -M '.interfaces.public[0].ipv4.gateway' $meta)
            public_ip4_nameserver1=$(cat /var/lib/cloud/seed/config_drive/openstack/content/000r | grep nameserver | cut -d' ' -f2 | head -n1)
            public_ip4_nameserver2=$(cat /var/lib/cloud/seed/config_drive/openstack/content/000r | grep nameserver | cut -d' ' -f2 | tail -n1)

            # public.ipv6.ip_address
            public_ip6_addr=$(jq -r -M '.interfaces.public[0].ipv6.ip_address' $meta)
            public_ip6_subnet=$(jq -r -M '.interfaces.public[0].ipv6.cidr' $meta)
            public_ip6_gateway=$(jq -r -M '.interfaces.public[0].ipv6.gateway' $meta)
        fi

        # private interface
        if [ ! -z $private_interface_mac ]; then
            # private.ipv4.ip_address
            private_ip4_addr=$(jq -r -M '.interfaces.private[0].ipv4.ip_address' $meta)
            private_ip4_subnet=$(opnsense_ipv4masktosubnet $(jq -r -M '.interfaces.private[0].ipv4.netmask' $meta))

            # private.ipv6.ip_address
            # TODO: this requires testing and confirmation !!
            private_ip6_addr="null"
            private_ip6_subnet="128"
        fi

        # =====================================================================

        echo "OPNsense Syshook: applying ssh-key to root account in $CONFIGFILE"

        # root user ssh key
        opnsense_config upsert "//system/user[contains(name,'root')]/authorizedkeys" "$root_sshkey_data" \
            || echo "OPNsense Syshook: failed to create //system/user[contains(name,'root')]/authorizedkeys"

        # =====================================================================

        echo "OPNsense Syshook: applying Instance IP address configuration data to $CONFIGFILE"

        # inject AWS provided nameservers if none are set
        if [ -z $(opnsense_config read "//system/dnsserver[1]") ]; then
            opnsense_config create "//system/dnsserver" "$public_ip4_nameserver1" \
                || echo "OPNsense Syshook: failed to create //system/dnsserver[1]"
            opnsense_config create "//system/dnsserver" "$public_ip4_nameserver2" \
                || echo "OPNsense Syshook: failed to create //system/dnsserver[2]"
        fi

        # inject public_ip4 address data if available
        if [ ! -z $public_ip4_addr ] && [ $public_ip4_addr != "null" ]; then
            opnsense_config update "//interfaces/public/ipaddr" "$public_ip4_addr" \
                || echo "OPNsense Syshook: failed to update //interfaces/public/ipaddr"
            opnsense_config update "//interfaces/public/subnet" "$public_ip4_subnet" \
                || echo "OPNsense Syshook: failed to update //interfaces/public/subnet"
            opnsense_config update "//gateways/gateway_item[contains(name,'public4gw')]/gateway" "$public_ip4_gateway" \
                || echo "OPNsense Syshook: failed to update //gateways/gateway_item[contains(name,'public4gw')]/gateway"
            opnsense_config delete "//gateways/gateway_item[contains(name,'public4gw')]/disabled" \
                || echo "OPNsense Syshook: failed to delete //gateways/gateway_item[contains(name,'public4gw')]/disabled"
            echo -n "OPNsense Syshook: Applying IPv4 to $public_interface: "
        else
            opnsense_config update "//interfaces/public/ipaddr" "null" \
                || echo "OPNsense Syshook: failed to update //interfaces/public/ipaddr"
            opnsense_config update "//interfaces/public/subnet" "32" \
                || echo "OPNsense Syshook: failed to update //interfaces/public/subnet"
            opnsense_config update "//gateways/gateway_item[contains(name,'public4gw')]/gateway" "disabled" \
                || echo "OPNsense Syshook: failed to update //gateways/gateway_item[contains(name,'public4gw')]/gateway"
            opnsense_config create "//gateways/gateway_item[contains(name,'public4gw')]/disabled" "1" \
                || echo "OPNsense Syshook: failed to create //gateways/gateway_item[contains(name,'public4gw')]/disabled"
            echo -n "OPNsense Syshook: Removing IPv4 on $public_interface: "
        fi
        /usr/local/opnsense/service/configd_ctl.py interface newip $public_interface

        # inject public_ip6 address data if available
        if [ ! -z $public_ip6_addr ] && [ $public_ip6_addr != "null" ]; then
            opnsense_config upsert "//interfaces/public/ipaddrv6" "$public_ip6_addr" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/public/ipaddrv6"
            opnsense_config upsert "//interfaces/public/subnetv6" "$public_ip6_subnet" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/public/subnetv6"
            opnsense_config upsert "//gateways/gateway_item[contains(name,'public6gw')]/gateway" "$public_ip6_gateway" \
                || echo "OPNsense Syshook: failed to upsert //gateways/gateway_item[contains(name,'public6gw')]/gateway"
            opnsense_config delete "//gateways/gateway_item[contains(name,'public6gw')]/disabled" \
                || echo "OPNsense Syshook: failed to delete //gateways/gateway_item[contains(name,'public6gw')]/disabled"
            echo -n "OPNsense Syshook: Applying IPv6 on $public_interface: "
        else
            opnsense_config upsert "//interfaces/public/ipaddrv6" "null" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/public/ipaddrv6"
            opnsense_config upsert "//interfaces/public/subnetv6" "128" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/public/subnetv6"
            opnsense_config upsert "//gateways/gateway_item[contains(name,'public6gw')]/gateway" "disabled" \
                || echo "OPNsense Syshook: failed to upsert //gateways/gateway_item[contains(name,'public6gw')]/gateway"
            opnsense_config create "//gateways/gateway_item[contains(name,'public6gw')]/disabled" "1" \
                || echo "OPNsense Syshook: failed to create //gateways/gateway_item[contains(name,'public6gw')]/disabled"
            echo -n "OPNsense Syshook: Removing IPv6 on $public_interface: "
        fi
       /usr/local/opnsense/service/configd_ctl.py interface newipv6 $public_interface

        # inject private_ip4 address data if available
        if [ ! -z $private_ip4_addr ] && [ $private_ip4_addr != "null" ]; then
            opnsense_config update "//interfaces/private/ipaddr" "$private_ip4_addr" \
                || echo "OPNsense Syshook: failed to update //interfaces/private/ipaddr"
            opnsense_config update "//interfaces/private/subnet" "$private_ip4_subnet" \
                || echo "OPNsense Syshook: failed to update //interfaces/private/subnet"
            echo -n "OPNsense Syshook: Applying IPv4 to $private_interface: "
        else
            opnsense_config update "//interfaces/private/ipaddr" "null" \
                || echo "OPNsense Syshook: failed to update //interfaces/private/ipaddr"
            opnsense_config update "//interfaces/private/subnet" "32" \
                || echo "OPNsense Syshook: failed to update //interfaces/private/subnet"
            echo -n "OPNsense Syshook: Removing IPv4 on $private_interface: "
        fi
        /usr/local/opnsense/service/configd_ctl.py interface newip $private_interface

        # inject private_ip6 address data if available
        if [ ! -z $private_ip6_addr ] && [ $private_ip6_addr != "null" ]; then
            opnsense_config upsert "//interfaces/private/ipaddrv6" "$private_ip6_addr" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/private/ipaddrv6"
            opnsense_config upsert "//interfaces/private/subnetv6" "$private_ip6_subnet" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/private/subnetv6"
            echo -n "OPNsense Syshook: Applying IPv6 on $private_interface: "
        else
            opnsense_config upsert "//interfaces/private/ipaddrv6" "null" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/private/ipaddrv6"
            opnsense_config upsert "//interfaces/private/subnetv6" "128" \
                || echo "OPNsense Syshook: failed to upsert //interfaces/private/subnetv6"
            echo -n "OPNsense Syshook: Removing IPv6 on $private_interface: "
        fi
        /usr/local/opnsense/service/configd_ctl.py interface newipv6 $private_interface

        # =====================================================================

        echo "OPNsense Syshook: finished instance configuration"
}

opnsense_main
exit 0
