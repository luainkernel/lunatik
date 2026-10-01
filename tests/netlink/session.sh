#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.session over a fake socket: dump() terminates (does not hang)
# on an empty read; dump() drains a MULTI reply that never sends DONE down to
# the empty read; talk() drains the reply up to the kernel acknowledgment,
# keeping a data reply and passing a zero error code; talk() raises the bare
# symbolic error name on a kernel error reply; and the flags come last and
# optional, request() sending NLM_F_REQUEST alone without them and talk()
# sending the ones it is given beside NLM_F_ACK; netlink.genl's talk() sends
# its command in the generic netlink header and the flags it is given.
#
# Usage: sudo bash tests/netlink/session.sh

SCRIPT="tests/netlink/session"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

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

dmesg | grep -q "netlink session: dump drains a MULTI reply ok" || fail "dump did not drain a MULTI reply"
ktap_pass "session: dump drains a MULTI reply to the empty read"

dmesg | grep -q "netlink session: talk drains the ack" || fail "talk did not drain the ack"
ktap_pass "session: talk drains the trailing ack"

dmesg | grep -q "netlink session: talk raises on error" || fail "talk did not raise on error"
ktap_pass "session: talk raises on a netlink error"

dmesg | grep -q "netlink session: flags last and optional" || fail "request or talk sent the wrong flags"
ktap_pass "session: flags come last and optional in request and talk"

dmesg | grep -q "netlink session: genl talk sends command and flags" || fail "genl talk sent the wrong command or flags"
ktap_pass "session: genl talk takes the command, the payload and the flags last"

ktap_totals

