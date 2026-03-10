#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test: calling runner.spawn() during module load must not hang.
#
# Prior to the fix, thread.run() (invoked by runner.spawn) called kthread_run()
# which blocks in wait_for_completion() during script load, hanging the system.
# The fix guards thread.run() with lunatik_isready() and returns an error
# instead.
#
# Usage: sudo bash tests/thread/run_during_load.sh

SCRIPT="tests/thread/run_during_load"
TIMEOUT=5

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT"          2>/dev/null
	lunatik stop "tests/thread/dummy" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
output=$(timeout $TIMEOUT lunatik run "$SCRIPT" 2>&1)
[ $? -eq 124 ] && fail "thread.run() hung during module load"
echo "$output" | sed 's/^/# (expected) /'

echo "$output" | grep -q "not allowed during module load" || \
	fail "expected 'not allowed during module load' error not found"
ktap_pass "runner.spawn() during module load returns error instead of hanging"

ktap_totals

