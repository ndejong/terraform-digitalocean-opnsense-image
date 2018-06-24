#!/bin/sh

# PROVIDE: digitaloceanopnsense
# REQUIRE: FILESYSTEMS
# BEFORE: LOGIN

. /etc/rc.subr

name="digitaloceanopnsense"
rcvar="digitaloceanopnsense_enable"
start_cmd="digitaloceanopnsense_start"
stop_cmd=":"


__digitaloceanopnsense_config_mangle()
{
    unset xpath
    unset attribute
    unset value

    xpath="$1"
    attribute="$2"
    value="$3"
    config_file="/conf/config.xml"

    old_string=`xmllint --xpath "$xpath" $config_file`
    new_string="<$attribute>$value</$attribute>"

#    echo ""
#    echo "xpath: $xpath"
#    echo "attribute: $attribute"
#    echo "value: $value"
#    echo "old_string: $old_string"
#    echo "new_string: $new_string"

    # Only replace if there is one match for the old_string value else we could be adjusting something unexpected
    if [ `cat $config_file | grep "$old_string" | wc -l` -eq 1 ]; then
        cat $config_file | sed "s|$old_string|$new_string|g" > /tmp/config.string_replaced
        mv /tmp/config.string_replaced $config_file
        return 0
    fi

    return 1
}

__digitaloceanopnsense_ipv4_mask_to_subnet()
{
    case $1 in

        "255.240.0.0")
            subnet=12
            ;;
        "255.248.0.0")
            subnet=13
            ;;
        "255.252.0.0")
            subnet=14
            ;;
        "255.254.0.0")
            subnet=15
            ;;
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

digitaloceanopnsense_start()
{
        jq="/usr/local/bin/jq"
        meta="/var/lib/cloud/seed/config_drive/digitalocean_meta_data.json"

        # Mount up the ConfigDrive
        echo "DigitalOcean OPNsense: mount configdrive"
        mkdir -p /var/lib/cloud/seed/config_drive
        mount_cd9660  -o ro -v /dev/vtbd1 /var/lib/cloud/seed/config_drive || echo "DigitalOcean OPNsense: failed to mount config drive"

        echo "DigitalOcean OPNsense: acquiring droplet IP address configuration"

        # interfaces
        public_interface=`xmllint --xpath "//interfaces/public/if" /conf/config.xml | sed 's|<if>||g' | sed 's|</if>||g'`
        private_interface=`xmllint --xpath "//interfaces/private/if" /conf/config.xml | sed 's|<if>||g' | sed 's|</if>||g'`

        # public.ipv4.ip_address
        public_ip4_addr=$($jq -r -M '.interfaces.public[0].ipv4.ip_address' $meta)
        public_ip4_mask=$($jq -r -M '.interfaces.public[0].ipv4.netmask' $meta)
        public_ip4_gateway=$($jq -r -M '.interfaces.public[0].ipv4.gateway' $meta)

        # public.ipv6.ip_address
        public_ip6_addr=$($jq -r -M '.interfaces.public[0].ipv6.ip_address' $meta)
        public_ip6_cidr=$($jq -r -M '.interfaces.public[0].ipv6.cidr' $meta)
        public_ip6_gateway=$($jq -r -M '.interfaces.public[0].ipv6.gateway' $meta)

        # private.ipv4.ip_address
        private_ip4_addr=$($jq -r -M '.interfaces.private[0].ipv4.ip_address' $meta)
        private_ip4_mask=$($jq -r -M '.interfaces.private[0].ipv4.netmask' $meta)

        if [ -f /etc/resolv.conf ]; then
            if [ `cat /etc/resolv.conf | grep 'nameserver' | wc -l | tr -d ' '` -lt 1 ]; then
                if [ -f /var/lib/cloud/seed/config_drive/openstack/content/000r ]; then
                    cat /var/lib/cloud/seed/config_drive/openstack/content/000r >> /etc/resolv.conf
                fi
            fi
        fi

        if [ ! -z $public_ip4_addr ]; then
            __digitaloceanopnsense_config_mangle "//interfaces/public/ipaddr" "ipaddr" "$public_ip4_addr"
            __digitaloceanopnsense_config_mangle "//interfaces/public/subnet" "subnet" `__digitaloceanopnsense_ipv4_mask_to_subnet $public_ip4_mask`
            __digitaloceanopnsense_config_mangle "//gateways/gateway_item[contains(name,'public4gw')]/gateway" "gateway" "$public_ip4_gateway"
            __digitaloceanopnsense_config_mangle "//gateways/gateway_item[contains(name,'public4gw')]/monitor" "monitor" "$public_ip4_gateway"
            __digitaloceanopnsense_config_mangle "//gateways/gateway_item[contains(name,'public4gw')]/disabled" "disabled" "0"
            /usr/local/opnsense/service/configd_ctl.py interface newip $public_interface
        fi

        if [ ! -z $public_ip6_addr ]; then
            __digitaloceanopnsense_config_mangle "//interfaces/public/ipaddrv6" "ipaddrv6" "$public_ip6_addr"
            __digitaloceanopnsense_config_mangle "//interfaces/public/subnetv6" "subnetv6" "$public_ip6_cidr"
            __digitaloceanopnsense_config_mangle "//gateways/gateway_item[contains(name,'public6gw')]/gateway" "gateway" "$public_ip6_gateway"
            __digitaloceanopnsense_config_mangle "//gateways/gateway_item[contains(name,'public6gw')]/monitor" "monitor" "$public_ip6_gateway"
            __digitaloceanopnsense_config_mangle "//gateways/gateway_item[contains(name,'public6gw')]/disabled" "disabled" "0"
           /usr/local/opnsense/service/configd_ctl.py interface newipv6 $public_interface
        fi

        if [ ! -z $private_ip4_addr ]; then
            __digitaloceanopnsense_config_mangle "//interfaces/private/ipaddr" "ipaddr" "$private_ip4_addr"
            __digitaloceanopnsense_config_mangle "//interfaces/private/subnet" "subnet" `__digitaloceanopnsense_ipv4_mask_to_subnet $private_ip4_mask`
        fi

        echo "DigitalOcean OPNsense: finished droplet configuration"
}

load_rc_config "$name"
run_rc_command "$1"
