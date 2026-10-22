#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that skb:ifname reads the name of the device the skb holds, as the device carries it when
# the callback runs, and nil on an skb that holds none.
#
# A veth pair joins the initial namespace to one of the test's own, where the peer carries a VLAN
# sub-interface. Once the script is loaded, the end in the initial namespace gets a VLAN
# sub-interface of its own, PORT, enslaved to a bridge: a datagram the namespace sends over its
# sub-interface arrives untagged on PORT, which is skb->dev at the bridge's PRE_ROUTING hook, and
# the hook reads the name PORT took after the script loaded. Renamed to RENAMED, of IFNAMSIZ - 1
# bytes, the longest name a device takes, PORT reads RENAMED whole on the next datagram, where a
# build that bounds the copy a byte short reads it cut. A datagram the initial namespace sends to
# itself reaches the IPv4 LOCAL_OUT hook before ip_output gives it a device, and reads nil. Both
# hooks read the datagrams whose payload begins with TAG, print the case the payload names beside
# the name, and drop them. Skips without socat, veth, a bridge or 8021q.
#
# Usage: sudo bash tests/skb/ifname.sh

SCRIPT="tests/skb/ifname"
IFACE="lunatikifn0"
PEER="lunatikifn1"
BRIDGE="lunatikifnbr"
NETNS="lunatik_ifname"
VLAN=42
PORT="$IFACE.$VLAN"
RENAMED="lunatikrenamed0" # IFNAMSIZ - 1 bytes
TARGET="10.199.7.1"
SOURCE="10.199.7.2"
UDP_PORT=5571
TAG="lunatik ifname " # TAG in ifname.lua
CREATED="ifname reads a device created after the script loaded"
RENAME="ifname reads the whole name a rename gave"
NODEV="ifname is nil on an skb with no device"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$IFACE" 2>/dev/null
	ip link del "$BRIDGE" 2>/dev/null
}
trap cleanup EXIT
cleanup

skip_all() {
	echo "# SKIP: $1"
	ktap_skip "$CREATED"
	ktap_skip "$RENAME"
	ktap_skip "$NODEV"
	ktap_skip "no Lua errors, kernel warnings or oopses"
	ktap_totals
	exit 0
}

# sent <case> <address> [<command>...]: sends, through the command, a datagram to the address whose
# payload names the case, and answers whether a hook read one
sent() {
	local case="$1" address="$2"
	shift 2
	printf '%s' "$TAG$case" | "$@" socat -u - "UDP:$address:$UDP_PORT" 2> /dev/null
	dmesg_since | grep -q "skb ifname: $case "
}

# reads <case>: the names the hooks read on the datagrams of the case, in the order they read them
reads() {
	echo "$out" | sed -n "s/.*skb ifname: $1 \(.*\)$/\1/p"
}

verdict() {
	local read="$1" want="$2" title="$3"
	if [ "$read" = "$want" ]; then
		ktap_pass "$title"
	else
		ktap_fail "$title"
		comment "read: ${read:-nothing}, want: $want"
	fi
}

ktap_header
ktap_plan 4

command -v socat > /dev/null 2>&1 || skip_all "socat unavailable"

ip netns add "$NETNS"
ip link add "$IFACE" type veth peer name "$PEER" netns "$NETNS" 2> /dev/null || skip_all "cannot create a veth pair"
ip link add "$BRIDGE" type bridge 2> /dev/null || skip_all "cannot create a bridge"
ip -n "$NETNS" link add link "$PEER" name "$PEER.$VLAN" type vlan id "$VLAN" 2> /dev/null ||
	skip_all "cannot create a VLAN sub-interface"
ip -n "$NETNS" addr add "$SOURCE/24" dev "$PEER.$VLAN"
ip link set "$BRIDGE" up
ip link set "$IFACE" up
ip -n "$NETNS" link set "$PEER" up
ip -n "$NETNS" link set "$PEER.$VLAN" up
# pin the neighbor entry so ARP never holds a datagram back
ip -n "$NETNS" neigh replace "$TARGET" lladdr "$(cat "/sys/class/net/$IFACE/address")" dev "$PEER.$VLAN" \
	nud permanent

mark_dmesg
run_script --context=softirq "$SCRIPT"

ip link add link "$IFACE" name "$PORT" type vlan id "$VLAN"
ip link set "$PORT" master "$BRIDGE"
ip link set "$PORT" up
awaited sent created "$TARGET" ip netns exec "$NETNS"
ip link set "$PORT" name "$RENAMED"
awaited sent renamed "$TARGET" ip netns exec "$NETNS"
awaited sent nodev 127.0.0.1
lunatik stop "$SCRIPT"

out=$(dmesg_since)
# the first: a datagram still queued when the rename returns reads the new name
verdict "$(reads created | head -1)" "$PORT" "$CREATED"
verdict "$(reads renamed | sort -u)" "$RENAMED" "$RENAME"
verdict "$(reads nodev | sort -u)" nil "$NODEV"
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

