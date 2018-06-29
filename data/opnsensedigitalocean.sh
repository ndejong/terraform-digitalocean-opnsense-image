#!/bin/sh

__opnsensedigitalocean_ipv4_mask_to_subnet()
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

__opnsensedigitalocean_config()
{
    configfile="/conf/config.xml"
    tempfile="/tmp/config-xmlstarlet-edit-`date -u +%Y%m%dZ%H%M%S`-`head /dev/urandom | md5 | head -c4`.tmp"

    method="$1"
    xpath="$2"
    value="$3"

    # CRUD - create
    if [ $method == "create" ]; then
        name=$(echo "$xpath" | rev | cut -f1 -d'/' | rev)
        xpath_sub=$(echo "$xpath" | rev | cut -f2- -d'/' | rev)
        xml ed -P -s "$xpath_sub" -t "elem" -n "$name" -v "$value" "$configfile" > "$tempfile"
        if [ $(xml sel -t -v "$xpath" "$tempfile" | tail -n1) == "$value" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # CRUD - read
    elif [ $method == "read" ]; then
        echo "$(xml sel -t -v "$xpath" "$configfile")"
        return 0

    # CRUD - update
    elif [ $method == "update" ]; then
        xml ed -P -u "$xpath" -v "$value" "$configfile" > "$tempfile"
        if [ $(xml sel -t -v "$xpath" "$tempfile") == "$value" ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # CRUD - delete
    elif [ $method == "delete" ]; then
        xml ed -P -d "$xpath" "$configfile" > "$tempfile"
        if [ -z $(xml sel -t -v "$xpath" "$tempfile") ]; then
            mv "$tempfile" "$configfile"
            return 0
        fi

    # CRUD - upsert
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

opnsensedigitalocean_start()
{
        meta="/var/lib/cloud/seed/config_drive/digitalocean_meta_data.json"

        # Mount the Digital Ocean config_drive if not already
        if [ $(mount | grep '/dev/vtbd1' | wc -l | tr -d ' ') -lt 1 ]; then
            echo "OPNsense DigitalOcean: mount config_drive"
            mkdir -p /var/lib/cloud/seed/config_drive
            mount_cd9660  -o ro -v /dev/vtbd1 /var/lib/cloud/seed/config_drive || echo "OPNsense DigitalOcean: failed to mount config drive"
        else
            echo "OPNsense DigitalOcean: config_drive already mounted"
        fi

        echo "OPNsense DigitalOcean: acquiring Droplet IP address configuration attributes"

        # interfaces
        public_interface=$(__opnsensedigitalocean_config read "//interfaces/public/if")
        private_interface=$(__opnsensedigitalocean_config read "//interfaces/private/if")

        # public.ipv4.ip_address
        public_ip4_addr=$(jq -r -M '.interfaces.public[0].ipv4.ip_address' $meta)
        public_ip4_mask=$(jq -r -M '.interfaces.public[0].ipv4.netmask' $meta)
        public_ip4_gateway=$(jq -r -M '.interfaces.public[0].ipv4.gateway' $meta)
        public_ip4_nameserver1=$(cat /var/lib/cloud/seed/config_drive/openstack/content/000r | grep nameserver | cut -d' ' -f2 | head -n1)
        public_ip4_nameserver2=$(cat /var/lib/cloud/seed/config_drive/openstack/content/000r | grep nameserver | cut -d' ' -f2 | tail -n1)

        # public.ipv6.ip_address
        public_ip6_addr=$(jq -r -M '.interfaces.public[0].ipv6.ip_address' $meta)
        public_ip6_cidr=$(jq -r -M '.interfaces.public[0].ipv6.cidr' $meta)
        public_ip6_gateway=$(jq -r -M '.interfaces.public[0].ipv6.gateway' $meta)

        # private.ipv4.ip_address
        private_ip4_addr=$(jq -r -M '.interfaces.private[0].ipv4.ip_address' $meta)
        private_ip4_mask=$(jq -r -M '.interfaces.private[0].ipv4.netmask' $meta)

        # root_sshkey_data
        root_sshkey_data=$(jq -r -M '.public_keys[0]' $meta | cut -d' ' -f2)


        # =====================================================================


        echo "OPNsense DigitalOcean: applying ssh-key to root account in /conf/config.xml"

        __opnsensedigitalocean_config upsert "//system/user[contains(name,'root')]/authorizedkeys" "$root_sshkey_data" \
            || echo "OPNsense DigitalOcean: failed to create //system/user[contains(name,'root')]/authorizedkeys"


        # =====================================================================


        echo "OPNsense DigitalOcean: applying Droplet IP address configuration data to /conf/config.xml"

        # inject Digital Ocean provided nameservers if none have been set
        if [ -z $(__opnsensedigitalocean_config read "//system/dnsserver[1]") ]; then
            __opnsensedigitalocean_config create "//system/dnsserver" "$public_ip4_nameserver1" \
                || echo "OPNsense DigitalOcean: failed to create //system/dnsserver[1]"
            __opnsensedigitalocean_config create "//system/dnsserver" "$public_ip4_nameserver2" \
                || echo "OPNsense DigitalOcean: failed to create //system/dnsserver[2]"
        fi

        # inject private_ip4 address data if offered
        if [ ! -z $private_ip4_addr ] && [ $private_ip4_addr != "null" ]; then

            __opnsensedigitalocean_config update "//interfaces/private/ipaddr" "$private_ip4_addr" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/private/ipaddr"

            __opnsensedigitalocean_config update "//interfaces/private/subnet" $(__opnsensedigitalocean_ipv4_mask_to_subnet "$private_ip4_mask") \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/private/subnet"

            __opnsensedigitalocean_config upsert "//interfaces/private/enable" "1" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/private/enable"

            echo -n "OPNsense DigitalOcean: Applying private IPv4 to $private_interface: "

        else
            __opnsensedigitalocean_config update "//interfaces/private/ipaddr" "null" \
                || echo "OPNsense DigitalOcean: failed to upsert //interfaces/private/ipaddr"

            __opnsensedigitalocean_config update "//interfaces/private/subnet" "32" \
                || echo "OPNsense DigitalOcean: failed to upsert //interfaces/private/subnet"

            __opnsensedigitalocean_config delete "//interfaces/private/enable" \
                || echo "OPNsense DigitalOcean: failed to remove //interfaces/private/enable"

            echo -n "OPNsense DigitalOcean: Removing private IPv4 on $private_interface: "
        fi
        /usr/local/opnsense/service/configd_ctl.py interface newip $private_interface

        echo -n "OPNsense DigitalOcean: Reconfiguring $private_interface: "
        /usr/local/opnsense/service/configd_ctl.py interface reconfigure $private_interface

        # inject public_ip4 address data if offered
        if [ ! -z $public_ip4_addr ] && [ $public_ip4_addr != "null" ]; then

            __opnsensedigitalocean_config update "//interfaces/public/ipaddr" "$public_ip4_addr" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/ipaddr"

            __opnsensedigitalocean_config update "//interfaces/public/subnet" $(__opnsensedigitalocean_ipv4_mask_to_subnet "$public_ip4_mask") \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/subnet"

            __opnsensedigitalocean_config update "//gateways/gateway_item[contains(name,'public4gw')]/gateway" "$public_ip4_gateway" \
                || echo "OPNsense DigitalOcean: failed to set //gateways/gateway_item[contains(name,'public4gw')]/gateway"

            __opnsensedigitalocean_config delete "//gateways/gateway_item[contains(name,'public4gw')]/disabled" \
                || echo "OPNsense DigitalOcean: failed to remove //gateways/gateway_item[contains(name,'public4gw')]/disabled"

            echo -n "OPNsense DigitalOcean: Applying public IPv4 to $public_interface: "

        else
            __opnsensedigitalocean_config update "//interfaces/public/ipaddr" "null" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/ipaddr"

            __opnsensedigitalocean_config update "//interfaces/public/subnet" "32" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/subnet"

            __opnsensedigitalocean_config update "//gateways/gateway_item[contains(name,'public4gw')]/gateway" "null" \
                || echo "OPNsense DigitalOcean: failed to set //gateways/gateway_item[contains(name,'public4gw')]/gateway"

            __opnsensedigitalocean_config create "//gateways/gateway_item[contains(name,'public4gw')]/disabled" "1" \
                || echo "OPNsense DigitalOcean: failed to set //gateways/gateway_item[contains(name,'public4gw')]/disabled"

            echo -n "OPNsense DigitalOcean: Removing public IPv4 on $public_interface: "
        fi
        /usr/local/opnsense/service/configd_ctl.py interface newip $public_interface

        # inject public_ip6 address data if offered
        if [ ! -z $public_ip6_addr ] && [ $public_ip6_addr != "null" ]; then

             __opnsensedigitalocean_config update "//interfaces/public/ipaddrv6" "$public_ip6_addr" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/ipaddrv6"

            __opnsensedigitalocean_config update "//interfaces/public/subnetv6" "$public_ip6_cidr" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/subnetv6"

            __opnsensedigitalocean_config update "//gateways/gateway_item[contains(name,'public6gw')]/gateway" "$public_ip6_gateway" \
                || echo "OPNsense DigitalOcean: failed to set //gateways/gateway_item[contains(name,'public6gw')]/gateway"

            __opnsensedigitalocean_config delete "//gateways/gateway_item[contains(name,'public6gw')]/disabled" \
                || echo "OPNsense DigitalOcean: failed to remove //gateways/gateway_item[contains(name,'public6gw')]/disabled"

            echo -n "OPNsense DigitalOcean: Applying public IPv6 to $public_interface: "

        else
            __opnsensedigitalocean_config update "//interfaces/public/ipaddrv6" "null" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/ipaddrv6"

            __opnsensedigitalocean_config update "//interfaces/public/subnetv6" "32" \
                || echo "OPNsense DigitalOcean: failed to set //interfaces/public/subnetv6"

            __opnsensedigitalocean_config update "//gateways/gateway_item[contains(name,'public6gw')]/gateway" "null" \
                || echo "OPNsense DigitalOcean: failed to set //gateways/gateway_item[contains(name,'public6gw')]/gateway"

            __opnsensedigitalocean_config create "//gateways/gateway_item[contains(name,'public6gw')]/disabled" "1" \
                || echo "OPNsense DigitalOcean: failed to set //gateways/gateway_item[contains(name,'public6gw')]/disabled"

            echo -n "OPNsense DigitalOcean: Removing public IPv6 on $public_interface: "
        fi
       /usr/local/opnsense/service/configd_ctl.py interface newipv6 $public_interface

        echo -n "OPNsense DigitalOcean: Reconfiguring $public_interface: "
        /usr/local/opnsense/service/configd_ctl.py interface reconfigure $public_interface

        echo "OPNsense DigitalOcean: finished droplet configuration"
}

opnsensedigitalocean_start
exit 0
