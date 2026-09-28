#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests skb:copy() on a FRAGLIST GSO skb, on a GSO skb of another type and on a
# plain one.
#
# A veth pair joins the initial namespace to one of the test's own. The end in the
# initial namespace aggregates UDP with fraglist GRO (rx-gro-list), and the end in
# the other namespace segments UDP in software (tx-udp-segmentation off). A socat
# there sends one datagram of SEGMENTS segments with UDP_SEGMENT: the segments
# leave in one transmit, before the receive softirq runs, so one NAPI poll
# aggregates them into a single FRAGLIST GSO skb. A PRE_ROUTING hook on that end
# copies it, which raises "FRAGLIST GSO skbs cannot be copied" before the copy
# linearizes the packet; a build without the check raises "not enough memory"
# after skb_copy's WARN_ON_ONCE. A lone datagram of one segment arrives as a plain
# skb, whose copy has the length of the original. With the segmentation turned
# back on, a datagram of GSO_SEGMENTS segments crosses the veth as one UDP GSO skb,
# which GRO passes as it came, and its copy has the length of the original too.
# The hook tells the three apart by their length and drops them. Skips without
# veth, socat or ethtool, or on a veth without fraglist GRO.
#
# Usage: sudo bash tests/skb/copy.sh

SCRIPT="tests/skb/copy"
IFACE="lunatikcopy0"
PEER="lunatikcopy1"
NETNS="lunatik_copy"
TARGET="10.199.2.1"
SOURCE="10.199.2.2"
PORT=5565
SEGMENT=1000   # SEGMENT in copy.lua
SEGMENTS=8     # SEGMENTS in copy.lua
GSO_SEGMENTS=4 # GSO_SEGMENTS in copy.lua
SOL_UDP=17
UDP_SEGMENT=103
FRAGLIST="copy: refuses a FRAGLIST GSO skb"
PLAIN="copy: copies a plain skb"
GSO="copy: copies a GSO skb that is not FRAGLIST"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$IFACE" 2>/dev/null
}
trap cleanup EXIT
cleanup

skip_all() {
	echo "# SKIP: $1"
	ktap_skip "$FRAGLIST"
	ktap_skip "$PLAIN"
	ktap_skip "$GSO"
	ktap_skip "no Lua errors, kernel warnings or oopses"
	ktap_totals
	exit 0
}

verdict() {
	local cell="$1" title="$2"
	local failed=$(echo "$out" | grep -o "skb copy: $cell FAIL.*" | head -1)
	if [ -n "$failed" ]; then
		ktap_fail "$title: $failed"
	elif echo "$out" | grep -q "skb copy: $cell ok"; then
		ktap_pass "$title"
	else
		ktap_fail "$title: the hook never reached it"
	fi
}

# send <segments>: one datagram of that many SEGMENT bytes, with UDP_SEGMENT
send() {
	ip netns exec "$NETNS" socat -u -b $((SEGMENT * $1)) "OPEN:/dev/zero,readbytes=$((SEGMENT * $1))" \
		"UDP:$TARGET:$PORT,setsockopt-int=$SOL_UDP:$UDP_SEGMENT:$SEGMENT" 2> /dev/null
}

ktap_header
ktap_plan 4

command -v socat > /dev/null 2>&1 || skip_all "socat unavailable"
command -v ethtool > /dev/null 2>&1 || skip_all "ethtool unavailable"

ip netns add "$NETNS"
ip link add "$IFACE" type veth peer name "$PEER" netns "$NETNS" 2> /dev/null || skip_all "cannot create a veth pair"
ip addr add "$TARGET/30" dev "$IFACE"
ip -n "$NETNS" addr add "$SOURCE/30" dev "$PEER"
# keep IPv6's link-up traffic off the poll that aggregates the datagram
ip netns exec "$NETNS" sysctl -qw "net.ipv6.conf.$PEER.disable_ipv6=1" 2> /dev/null
ip link set "$IFACE" up
ip -n "$NETNS" link set "$PEER" up
ethtool -K "$IFACE" gro on rx-gro-list on 2> /dev/null || skip_all "no fraglist GRO on veth"
ip netns exec "$NETNS" ethtool -K "$PEER" tx-udp-segmentation off 2> /dev/null ||
	skip_all "cannot turn UDP segmentation offload off on veth"

# pin the neighbor entries so ARP never holds a datagram back
MAC=$(cat "/sys/class/net/$IFACE/address")
PEER_MAC=$(ip netns exec "$NETNS" cat "/sys/class/net/$PEER/address")
ip neigh replace "$SOURCE" lladdr "$PEER_MAC" dev "$IFACE" nud permanent
ip -n "$NETNS" neigh replace "$TARGET" lladdr "$MAC" dev "$PEER" nud permanent

mark_dmesg
run_script --context=softirq "$SCRIPT"

send "$SEGMENTS"
send 1
ip netns exec "$NETNS" ethtool -K "$PEER" tx-udp-segmentation on
send "$GSO_SEGMENTS"

for _ in $(seq 20); do
	[ "$(dmesg_since | grep -c "skb copy: ")" -ge 3 ] && break
	sleep 0.5
done
lunatik stop "$SCRIPT"

out=$(dmesg_since)
verdict fraglist "$FRAGLIST"
verdict plain "$PLAIN"
verdict gso "$GSO"
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

