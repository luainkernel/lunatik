#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.link():set: creates a down dummy interface, brings it up via
# rtnetlink and asserts the IFF_UP flag is set in a dump, then brings it down
# and asserts the flag is cleared.
#
# Usage: sudo bash tests/netlink/link_updown.sh

SCRIPT="tests/netlink/link_updown"
MODULE="luasocket"
NAME="lunatikdummy0"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { ip link del "$NAME" 2>/dev/null; }
trap cleanup EXIT

ktap_header
ktap_plan 2

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

ip link add "$NAME" type dummy || { echo "# SKIP: cannot add dummy"; ktap_totals; exit 0; }

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink link_updown: brought up" || fail "link:set did not bring the interface up"
ktap_pass "link:set brings an interface up (IFF_UP set)"

dmesg | grep -q "netlink link_updown: brought down" || fail "link:set did not bring the interface down"
ktap_pass "link:set brings an interface down (IFF_UP cleared)"

ktap_totals

