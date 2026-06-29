#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.session over a fake socket: dump() terminates (does not hang)
# on an empty read; talk() drains the reply up to the kernel acknowledgment,
# keeping a data reply and passing a zero error code; and talk() raises the
# bare symbolic error name on a kernel error reply.
#
# Usage: sudo bash tests/netlink/session.sh

SCRIPT="tests/netlink/session"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

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

dmesg | grep -q "netlink session: dump empty-read ok" || fail "dump did not terminate on empty read"
ktap_pass "session: dump terminates on empty read"

dmesg | grep -q "netlink session: talk drains the ack" || fail "talk did not drain the ack"
ktap_pass "session: talk drains the trailing ack"

dmesg | grep -q "netlink session: talk raises on error" || fail "talk did not raise on error"
ktap_pass "session: talk raises on a netlink error"

ktap_totals

