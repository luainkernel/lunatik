#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An skb copy reads the device of the skb it was made from while the callback that received
# the original runs, and keeps the packet but not the device once that callback returns.
#
# copy_device.lua takes one step per echo request in PRE_ROUTING netfilter hooks and drops it:
# the pings to the loopback address marked STEP_MARK, and those a namespace of the test's own
# sends over a veth pair to its end in the initial namespace, IFACE:
#
# - inside: on lo, a copy and a copy of that copy, made in the callback, name the device skb
#   does with ifindex() and ifname(), and forward() sends each back out through lo under a
#   mark of its own, whose hook sees it arrive; a third copy, dropped and collected in the
#   callback, goes;
# - held: on IFACE, a copy names IFACE inside the callback;
# - past: from a later callback on lo, the three copies kept have no ifindex() nor ifname(),
#   their forward() raises "skb has no device", and their data() reads the echo request, and so
#   do a copy of each made then;
# - deleted: with IFACE deleted after past, which returns within BOUND seconds since no copy
#   holds the device, the copies answer as they did at past.
#
# A build whose copies keep the device past the callback fails past on the first copy's
# ifindex(), before its forward(), and the test then ends before it deletes IFACE, which such a
# copy would read once freed; one that clears the device as the copy is made fails inside on
# the first copy's ifindex(). Skips without veth.
#
# Usage: sudo bash tests/skb/copy_device.sh

SCRIPT="tests/skb/copy_device"
IFACE="lunatikcdev0" # IFACE in copy_device.lua
PEER="lunatikcdev1"
NETNS="lunatik_cdev"
TARGET="10.199.3.1"
SOURCE="10.199.3.2"
LOCAL="127.0.0.1"
STEP_MARK=1310 # STEP_MARK in copy_device.lua
BOUND=5
INSIDE="copy_device: a copy and a copy of it carry the device inside the callback, and forward() sends each"
PAST="copy_device: past the callback a copy has no device, forward() raises, and its bytes read, as a copy of it does"
DELETED="copy_device: deleting the device a copy came from waits on no copy and leaves what the copies answer"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

DONE=$(mktemp)

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$IFACE" 2>/dev/null
}
trap 'cleanup; rm -f "$DONE"' EXIT
cleanup

skip_all() {
	echo "# SKIP: $1"
	ktap_skip "$INSIDE"
	ktap_skip "$PAST"
	ktap_skip "$DELETED"
	ktap_skip "no Lua errors, kernel warnings or oopses"
	ktap_totals
	exit 0
}

reported() { dmesg_since | grep -q "skb copy device: $1 ok"; }
deleted() { [ -s "$DONE" ]; }

# sends the ping the hook takes <cell> on, and fails unless the hook reports it ok
step() {
	local cell="$1" failed
	shift
	"$@" > /dev/null 2>&1
	failed=$(dmesg_since | grep -o "skb copy device: $cell FAIL.*" | head -1)
	[ -z "$failed" ] || fail "$failed"
	reported "$cell" || fail "the hook never reached $cell"
}

ktap_header
ktap_plan 4

ip netns add "$NETNS"
ip link add "$IFACE" type veth peer name "$PEER" netns "$NETNS" 2> /dev/null || skip_all "cannot create a veth pair"
ip addr add "$TARGET/30" dev "$IFACE"
ip -n "$NETNS" addr add "$SOURCE/30" dev "$PEER"
ip link set "$IFACE" up
ip -n "$NETNS" link set "$PEER" up
# pin the neighbor entry so ARP never holds the echo request back
ip -n "$NETNS" neigh replace "$TARGET" lladdr "$(cat "/sys/class/net/$IFACE/address")" dev "$PEER" nud permanent

mark_dmesg
run_script --context=softirq "$SCRIPT"

step inside ping -c 1 -W 1 -m "$STEP_MARK" "$LOCAL"
awaited reported "sent copy" || fail "the copy forward() sent never arrived"
awaited reported "sent inner" || fail "the copy of the copy forward() sent never arrived"
step held ip netns exec "$NETNS" ping -c 1 -W 1 "$TARGET"
ktap_pass "$INSIDE"

step past ping -c 1 -W 1 -m "$STEP_MARK" "$LOCAL"
ktap_pass "$PAST"

(ip link del "$IFACE"; echo $? > "$DONE") &
TRIES=$((BOUND * 10)) awaited deleted || fail "deleting $IFACE waited over $BOUND s with a copy of its packet kept"
[ "$(cat "$DONE")" -eq 0 ] || fail "cannot delete $IFACE"
step deleted ping -c 1 -W 1 -m "$STEP_MARK" "$LOCAL"
ktap_pass "$DELETED"

lunatik stop "$SCRIPT"
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

