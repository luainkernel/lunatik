#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the name thread.run() gives its kernel task: the name is a
# string a script chooses and it reached kthread_run() as the format itself, so
# one carrying conversions made the kernel format varargs that were never
# passed. The task's comm must be the name as written.
#
# thread.run() is refused while a script loads, so the call is made from a thread
# body, which runs once the runtime that spawned it is ready.
#
# Usage: sudo bash tests/thread/name.sh

SCRIPT="tests/thread/name"
BODY="tests/thread/dummy"
SLEEP=1

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$BODY"   2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
sleep $SLEEP
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -qF "thread name: ok" || fail "the thread body did not report the name"
ktap_pass "thread.run() names the task with the string it is given"

ktap_totals

