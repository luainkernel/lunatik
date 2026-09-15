#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Drives the spawned examples/shared daemon over its own port with a kernel-side
# client: a GET of a key that was never assigned, and a GET of a key a SET
# removed, must each answer with an empty line rather than take the thread body
# down and leave the port bound with nobody in accept().
#
# Usage: sudo bash tests/examples/shared.sh

SCRIPT="tests/examples/shared_client"
EXAMPLE="examples/shared"
MODULE="luasocket"
SLEEP=1
BINDS=15
BIND_WAIT=5

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$EXAMPLE" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
# a run the daemon did not survive leaves its session for the runtime teardown to
# close, and that close sends the first FIN, so 127.0.0.1:90 sits in TIME_WAIT
# until TCP_TIMEWAIT_LEN; no bind gets past it without SO_REUSEADDR
for _ in $(seq 1 $BINDS); do
	spawned=$(lunatik spawn "$EXAMPLE" 2>&1)
	case "$spawned" in *EADDRINUSE*) sleep $BIND_WAIT ;; *) break ;; esac
done
[ -z "$spawned" ] || { comment "$spawned"; fail "$EXAMPLE did not spawn"; }
sleep $SLEEP

run_script "$SCRIPT"
cleanup

dmesg_since | grep -q "shared example: unset ok" || fail "a GET of a key never assigned did not answer"
ktap_pass "shared: a GET of a key that was never assigned answers with an empty line"

dmesg_since | grep -q "shared example: removed ok" || fail "a GET of a key a SET removed did not answer"
ktap_pass "shared: a GET of a key a SET removed answers with an empty line"

check_dmesg || { ktap_totals; exit 1; }

ktap_totals

