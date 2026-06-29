#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.route_add()/route_del(): adds a non-routable dummy route
# (192.0.2.0/24 via lo) in an isolated table, confirms it appears in a dump,
# deletes it, and confirms it is gone.
#
# Usage: sudo bash tests/netlink/route_adddel.sh

SCRIPT="tests/netlink/route_adddel"
MODULE="luanetlink"
TABLE=100

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { ip route flush table "$TABLE" 2>/dev/null; }
trap cleanup EXIT

ktap_header
ktap_plan 2

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

dmesg | grep -q "netlink route_adddel: deleted" || fail "route_del did not remove the route"
ktap_pass "route_del: dummy route removed"

ktap_totals

