#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.genl: resolves the always-present generic netlink controller
# family ("nlctrl") to GENL_ID_CTRL; then, on the SAME instance, a GETFAMILY
# call() round-trip (regression: family()/call() must drain the ACK so the
# socket stays in sync); a GETFAMILY dump() listing every family (nlctrl among
# them); and that an unknown family raises.
#
# Usage: sudo bash tests/netlink/genl_family.sh

SCRIPT="tests/netlink/genl_family"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 4

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink genl_family: nlctrl resolved" || fail "nlctrl family not resolved"
ktap_pass "genl_family: nlctrl resolves to GENL_ID_CTRL"

dmesg | grep -q "netlink genl_family: call round-trip ok" || fail "call() on the same instance failed (orphaned ACK?)"
ktap_pass "genl_family: GETFAMILY call() round-trip on the same instance"

dmesg | grep -q "netlink genl_family: dump lists families" || fail "dump() did not list the families"
ktap_pass "genl_family: GETFAMILY dump() lists the families"

dmesg | grep -q "netlink genl_family: missing family errors" || fail "missing family did not raise"
ktap_pass "genl_family: unknown family raises"

ktap_totals

