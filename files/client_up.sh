#!/bin/sh

# example client up script
# will be executed when client is up

# all key value pairs in ShadowVPN config file will be passed to this script
# as environment variables, except password

# turn on IP forwarding
sysctl -w net.ipv4.ip_forward=1>/dev/null 2>&1

# configure IP address and MTU of VPN interface
ifconfig $intf 10.7.0.2 netmask 255.255.255.0
ifconfig $intf mtu $mtu

# get current gateway and interface
echo "$(date) [UP] get gateway and interface from route table"
eval $(ip route show | awk '/^default/ {
	for (i=1; i<=NF; i++) {
		if ($i == "via") { printf("old_gw=%s;", $(i+1)) }
		if ($i == "dev") { printf("old_intf=%s;", $(i+1)) }
	}
}')

if [ -z "$old_intf" ]; then
	echo "$(date) [UP] failed to get interface from route table"
	exit 1
fi

# if current interface is tun, read from saved file.
if [ "$old_intf" = "$intf" ]; then
  echo "$(date) [UP] reading gateway and interface from saved file"
  old_gw=$(cat /tmp/old_gw) && old_intf=$(cat /tmp/old_intf) || {
    echo "$(date) [UP] can not read gateway or interface, check up.sh"
    exit 1
  }
fi

# save gateway and interface to file
echo $old_gw > /tmp/old_gw
echo $old_intf > /tmp/old_intf
echo "$(date) [UP] save gateway and interface to file"

# turn on NAT over VPN and old gateway
iptables -t nat -A POSTROUTING -o $intf -j MASQUERADE
iptables -A FORWARD -i $old_intf -o $intf -j ACCEPT
iptables -A FORWARD -i $intf -o $old_intf -j ACCEPT
iptables -D delegate_forward -j reject>/dev/null 2>&1

# change routing table
if [ -z "$old_gw" ]; then
  route add $server $old_intf
  suf="dev $old_intf"
else
  route add $server gw $old_gw
  suf="via $old_gw dev $old_intf"
fi
route del default
route add default gw 10.7.0.1
echo "$(date) [UP] default route changed to 10.7.0.1"

# chnroute list file, You can specify a custom routes list file.
chnroute=/etc/chinadns_chnroute.txt

# load chnroute rules
if [ -f $chnroute ]; then
  awk -v suf="$suf" '$1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}/\
    {printf("route add %s %s\n",$1,suf)}' $chnroute > /tmp/routes
  ip -batch /tmp/routes
  echo "$(date) [UP] chnroute rules loaded"
fi

echo "$(date) [UP] done"
