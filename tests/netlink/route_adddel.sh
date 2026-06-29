#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.route_add()/route_del(): adds a non-routable dummy route
# (192.0.2.0/24 via lo) in an isolated table whose id is > 255 (so it exercises
# the RTA_TABLE attribute path, not the u8 rtm_table), confirms it appears in a
# dump, asserts a duplicate add raises (NLM_F_EXCL -> EEXIST via check_error),
# deletes it, and confirms it is gone.
#
# Usage: sudo bash tests/netlink/route_adddel.sh

SCRIPT="tests/netlink/route_adddel"
MODULE="luasocket"
TABLE=1000

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { ip route flush table "$TABLE" 2>/dev/null; }
trap cleanup EXIT

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink route_adddel: added" || fail "route_add did not create the route"
ktap_pass "route_add: dummy route created and visible in dump"

dmesg | grep -q "netlink route_adddel: duplicate add raises" || fail "duplicate add did not raise"
ktap_pass "route_add: duplicate add raises (NLM_F_EXCL)"

dmesg | grep -q "netlink route_adddel: deleted" || fail "route_del did not remove the route"
ktap_pass "route_del: dummy route removed"

ktap_totals

