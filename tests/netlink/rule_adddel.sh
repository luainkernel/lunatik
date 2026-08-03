#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.rule():add/del: adds a FIB rule directing lookups to an
# isolated table whose id is > 255 (so it exercises the FRA_TABLE attribute,
# not the u8 header field), confirms it appears in a dump, asserts a duplicate
# add raises (NLM_F_EXCL -> EEXIST via check_error), deletes it, and confirms it
# is gone; then repeats add/del with a table id that fits the u8 header field,
# exercising the header-side id path (no FRA_TABLE).
#
# Usage: sudo bash tests/netlink/rule_adddel.sh

SCRIPT="tests/netlink/rule_adddel"
MODULE="luasocket"
PRIO=32100
SMALL_PRIO=32101

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	ip rule del priority "$PRIO" 2>/dev/null
	ip rule del priority "$SMALL_PRIO" 2>/dev/null
}
trap cleanup EXIT

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

dmesg | grep -q "netlink rule_adddel: added" || fail "rule_add did not create the rule"
ktap_pass "rule_add: rule created and visible in dump"

dmesg | grep -q "netlink rule_adddel: duplicate add raises" || fail "duplicate add did not raise"
ktap_pass "rule_add: duplicate add raises (NLM_F_EXCL)"

dmesg | grep -q "netlink rule_adddel: deleted" || fail "rule_del did not remove the rule"
ktap_pass "rule_del: rule removed"

dmesg | grep -q "netlink rule_adddel: small-table added" || fail "small-table add did not create the rule"
ktap_pass "rule_add: small-table rule created via the header id"

dmesg | grep -q "netlink rule_adddel: small-table deleted" || fail "small-table del did not remove the rule"
ktap_pass "rule_del: small-table rule removed"

ktap_totals

