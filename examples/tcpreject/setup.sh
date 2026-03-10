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
MARK=0x403

# namespace + veth pair
ip netns add $NETNS
ip link add $VETH_HOST type veth peer name $VETH_NS
ip link set $VETH_NS netns $NETNS
ip addr add $HOST_ADDR/24 dev $VETH_HOST
ip link set $VETH_HOST up
ip -n $NETNS addr add $NS_ADDR/24 dev $VETH_NS
ip -n $NETNS link set $VETH_NS up
ip -n $NETNS link set lo up
ip -n $NETNS route add default via $HOST_ADDR

# forwarding + masquerade so the namespace can reach the internet
echo 1 > /proc/sys/net/ipv4/ip_forward
nft add table ip tcpreject
nft add chain ip tcpreject postrouting \
	{ type nat hook postrouting priority srcnat \; }
nft add rule ip tcpreject postrouting \
	ip saddr $PREFIX masquerade

# mark TCP/853 to 8.8.8.8 at mangle priority (before the Lua FILTER hook)
nft add chain ip tcpreject forward \
	{ type filter hook forward priority mangle \; }
nft add rule ip tcpreject forward \
	ip daddr 8.8.8.8 tcp dport 443 mark set $MARK

# load the Lua hook
lunatik run examples/tcpreject/nf_tcpreject false

echo "setup done"
echo "test: ip netns exec $NETNS curl --connect-timeout 2 https://8.8.8.8"

