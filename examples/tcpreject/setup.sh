#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

set -eux

NETNS=tcpreject
VETH_HOST=veth-tcpreject
VETH_NS=veth-ns
HOST_ADDR=10.99.0.1
NS_ADDR=10.99.0.2
PREFIX=10.99.0.0/24
HOST_ADDR6=fd99::1
NS_ADDR6=fd99::2
PREFIX6=fd99::/64
DNS4=8.8.8.8
DNS6=2001:4860:4860::8888
MARK=0x403

# namespace + veth pair
ip netns add $NETNS
ip link add $VETH_HOST type veth peer name $VETH_NS
ip link set $VETH_NS netns $NETNS
ip addr add $HOST_ADDR/24 dev $VETH_HOST
ip -6 addr add $HOST_ADDR6/64 dev $VETH_HOST
ip link set $VETH_HOST up
ip -n $NETNS addr add $NS_ADDR/24 dev $VETH_NS
ip -n $NETNS -6 addr add $NS_ADDR6/64 dev $VETH_NS
ip -n $NETNS link set $VETH_NS up
ip -n $NETNS link set lo up
ip -n $NETNS route add default via $HOST_ADDR
ip -n $NETNS -6 route add default via $HOST_ADDR6

# forwarding + masquerade so the namespace can reach the internet
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
nft add table ip tcpreject
nft add chain ip tcpreject postrouting \
	{ type nat hook postrouting priority srcnat \; }
nft add rule ip tcpreject postrouting \
	ip saddr $PREFIX masquerade

# mark TCP/443 at mangle priority (before the Lua FILTER hook)
nft add chain ip tcpreject forward \
	{ type filter hook forward priority mangle \; }
nft add rule ip tcpreject forward \
	ip daddr $DNS4 tcp dport 443 mark set $MARK

nft add table ip6 tcpreject
nft add chain ip6 tcpreject forward \
	{ type filter hook forward priority mangle \; }
nft add rule ip6 tcpreject forward \
	ip6 daddr $DNS6 tcp dport 443 mark set $MARK

# load the Lua hook
lunatik run examples/tcpreject/nf_tcpreject false

echo "setup done"
echo "test IPv4: ip netns exec $NETNS curl --connect-timeout 2 https://$DNS4"
echo "test IPv6: ip netns exec $NETNS curl --connect-timeout 2 https://[$DNS6]"

