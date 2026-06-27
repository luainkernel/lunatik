#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.route_dump(): dumps the routing tables and verifies that
# at least one route is returned and its common fields are populated.
#
# Usage: sudo bash tests/netlink/route_dump.sh

SCRIPT="tests/netlink/route_dump"
MODULE="luanetlink"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

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

dmesg | grep -q "netlink route_dump: routes found" || fail "no routes returned by route_dump"
ktap_pass "route_dump: at least one route returned"

dmesg | grep -q "netlink route_dump: fields ok" || fail "route entry missing family/scope/rtype"
ktap_pass "route_dump: route entry has family, scope, rtype fields"

ktap_totals

