#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.genl: resolves the always-present generic netlink controller
# family ("nlctrl") to GENL_ID_CTRL; then, on the SAME instance, a GETFAMILY
# talk() round-trip (regression: family()/talk() must drain the ACK so the
# socket stays in sync); a GETFAMILY dump() listing every family (nlctrl among
# them); that linux.genl.ctrl.attr holds the controller's attributes and none
# of the nested CTRL_ATTR_OP_, MCAST_GRP_ and POLICY_ ones; and that an unknown
# family raises.
#
# Usage: sudo bash tests/netlink/genl_family.sh

SCRIPT="tests/netlink/genl_family"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

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

dmesg | grep -q "netlink genl_family: talk round-trip ok" || fail "talk() on the same instance failed (orphaned ACK?)"
ktap_pass "genl_family: GETFAMILY talk() round-trip on the same instance"

dmesg | grep -q "netlink genl_family: dump lists families" || fail "dump() did not list the families"
ktap_pass "genl_family: GETFAMILY dump() lists the families"

dmesg | grep -q "netlink genl_family: ctrl.attr holds the controller's attributes" || fail "linux.genl.ctrl.attr holds a nested attribute"
ktap_pass "genl_family: linux.genl.ctrl.attr holds the controller's attributes only"

dmesg | grep -q "netlink genl_family: missing family errors" || fail "missing family did not raise"
ktap_pass "genl_family: unknown family raises"

ktap_totals

