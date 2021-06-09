#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
        . /lib/functions.sh
        . ../netifd-proto.sh
        init_proto "$@"
}

proto_t2n_setup() {
        local cfg="$1"
        local device="t2n-$cfg"
        local server port server2 port2 mode ipaddr netmask gateway macaddr mtu community key forwarding ip6addr ip6prefixlen ip6gw dynamic localport mgmtport multicast verbose
        json_get_vars server port server2 port2 mode ipaddr netmask gateway macaddr mtu community key forwarding ip6addr ip6prefixlen ip6gw dynamic localport mgmtport multicast verbose

        proto_run_command "$cfg" /usr/sbin/t2n -f \
                          -d "$device" \
                          -l "${server}:${port}" \
                          $([ -n "$server2" -a -n "$port2" ] && echo -l "${server2}:${port2}") \
                          -u "$community" \
                          $([ -n "$key" ] && echo -k $key) \
                          $([ -n "$macaddr" ] && echo -m $macaddr) \
                          $([ -n "$mtu" ] && echo -M $mtu) \
                          $([ "$forwarding" = 1 ] && echo -r) \
                          $([ -n "$localport" ] && echo -p $localport) \
                          $([ -n "$mgmtport" ] && echo -t $mgmtport) \
                          $([ "$multicast" = 1 ] && echo -E) \
                          $([ "$verbose" = 1 ] && echo -v -v -v) \
                -S /usrdata/reconnect.sh \
                -P 24 \
                -L /root/t2n.log

        #proto_init_update "$device" 1
        #proto_set_keep 1
        #sleep 1

        #proto_add_ipv4_address "$ipaddr" "$netmask"

        #if [ -n "$ip6addr" ] && [ -n "$ip6prefixlen" ]; then
        #        ifconfig "$device" "${ip6addr}/${ip6prefixlen}"
        #        proto_add_ipv6_address "$ip6addr" "$ip6prefixlen"
        #fi

        #[ -n "$gateway" ] && {
        #        proto_add_ipv4_route 0.0.0.0 0 "$gateway"
        #}

        #[ -n "$ip6gw" ] && {
        #        proto_add_ipv6_route "::" 0 "$ip6gw"
        #}

        #proto_send_update "$cfg"
}

proto_t2n_teardown() {
        local cfg="$1"
        local device="t2n-$cfg"

        proto_init_update "$device" 0
        proto_kill_command "$1"
        kill -SIGKILL `cat /var/run/${device}.pid` >/dev/null 2>&1
        proto_send_update "$cfg"
}

proto_t2n_init_config() {
        no_device=1
        available=1

        proto_config_add_string "server"
        proto_config_add_int "port"
        proto_config_add_string "server2"
        proto_config_add_int "port2"
        proto_config_add_string "mode"
        proto_config_add_string "ipaddr"
        proto_config_add_string "netmask"
        proto_config_add_string "gateway"
        proto_config_add_string "macaddr"
        proto_config_add_int "mtu"
        proto_config_add_string "community"
        proto_config_add_string "key"
        proto_config_add_boolean "forwarding"
        proto_config_add_string "ip6addr"
        proto_config_add_int "ip6prefixlen"
        proto_config_add_string "ip6gw"
        proto_config_add_boolean "dynamic"
        proto_config_add_int "localport"
        proto_config_add_int "mgmtport"
        proto_config_add_boolean "multicast"
        proto_config_add_boolean "verbose"
}

[ -n "$INCLUDE_ONLY" ] || {
        add_protocol t2n
}
