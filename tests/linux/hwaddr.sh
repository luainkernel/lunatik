#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests linux.ifindex and linux.hwaddr, which resolve a device in the initial
# network namespace. The test creates the dummy DEV there, and MOVED, which it
# moves into a namespace of its own once it has read its index; the script finds
# that index in the module INDEXMOD. linux.ifindex resolves lo to 1 and DEV to
# the index sysfs gives it; linux.hwaddr answers lo's six zero bytes and DEV's
# address as sysfs spells it, its addr_len bytes. MOVED's name and index, which
# only the other namespace holds, each answer nil, as tests/linux/ifindex pins
# for a name and an index no device has. linux.hwaddr refuses as out of bounds
# an index outside 1 to INT_MAX: 0, -1, INT_MAX + 1, and lo's index past 32 bits,
# which a build that reads the index into an int answers with lo's address. The
# moved device keeps its index when the other namespace has none by that number,
# and the test skips when the initial namespace gave it to another device
# meanwhile.
#
# Usage: sudo bash tests/linux/hwaddr.sh

SCRIPT="tests/linux/hwaddr"
MODULE="lualinux"
NETNS="lunatik_hwaddr"
DEV="lunatikhw0"
MOVED="lunatikhw1"
INDEXMOD="/lib/modules/lua/tests/linux/hwaddr_index.lua"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip link del "$DEV" 2>/dev/null
	ip link del "$MOVED" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	rm -f "$INDEXMOD"
}
trap cleanup EXIT
cleanup

skip() { ktap_skip "$1"; ktap_totals; exit 0; }

ktap_header
ktap_plan 2

[ -e /sys/module/$MODULE ] || skip "linux/hwaddr: $MODULE not loaded"
ip link add "$DEV" type dummy 2>/dev/null || skip "linux/hwaddr: cannot create a dummy device"
ip link add "$MOVED" type dummy 2>/dev/null || skip "linux/hwaddr: cannot create a dummy device"
ip netns add "$NETNS" 2>/dev/null || skip "linux/hwaddr: cannot create a network namespace"
moved=$(cat "/sys/class/net/$MOVED/ifindex")
ip link set "$MOVED" netns "$NETNS" 2>/dev/null || skip "linux/hwaddr: cannot move a device into $NETNS"
[ "$(ip -n "$NETNS" -o link show "$MOVED" 2>/dev/null | cut -d: -f1)" = "$moved" ] ||
	skip "linux/hwaddr: $MOVED took another index in $NETNS"
ip -o link show | cut -d: -f1 | grep -qx "$moved" && skip "linux/hwaddr: index $moved was given to another device"
echo "return {moved = $moved}" > "$INDEXMOD"

run_test "$SCRIPT" || fail "linux.ifindex or linux.hwaddr answered a device wrong, or answered an index out of bounds"
ktap_pass "linux/hwaddr: ifindex and hwaddr answer a device of the initial namespace, nil for one of another, and refuse an index out of bounds"

cleanup
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

