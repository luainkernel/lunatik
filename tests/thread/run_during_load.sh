#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test: calling runner.spawn() from a script body must not hang,
# and the runtime the refused spawn created must not stay registered.
#
# Prior to the fix, thread.run() (invoked by runner.spawn) called kthread_run()
# which blocks in wait_for_completion() during script load, hanging the system.
# The fix guards thread.run() with lunatik_isready() and returns an error
# instead.
#
# Usage: sudo bash tests/thread/run_during_load.sh

SCRIPT="tests/thread/run_during_load"
DUMMY="tests/thread/dummy"
TIMEOUT=5

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT"          2>/dev/null
	lunatik stop "$DUMMY"           2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
output=$(timeout $TIMEOUT lunatik run "$SCRIPT" 2>&1)
[ $? -eq 124 ] && fail "thread.run() hung in the script body"
echo "$output" | sed 's/^/# (expected) /'

echo "$output" | grep -q "not allowed before the runtime is armed" || \
	fail "expected 'not allowed before the runtime is armed' error not found"
listed=$(lunatik list)
case "$listed" in
	*"$DUMMY"*) fail "the refused spawn left the runtime registered: $listed" ;;
esac
ktap_pass "runner.spawn() from a script body returns error instead of hanging"

ktap_totals

