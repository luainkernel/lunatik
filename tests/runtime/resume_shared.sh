#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test: runtime:resume() must correctly pass shared (monitored)
# objects across runtime boundaries. Pushes a value into a shared fifo,
# passes it to a sub-runtime via resume(), and asserts the value can be popped.
#
# Usage: sudo bash tests/runtime/resume_shared.sh

SCRIPT="tests/runtime/resume_shared"
MODULE="luafifo"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

lunatik run "$SCRIPT"

check_dmesg || exit 1
ktap_pass "resume with shared fifo object succeeded"

ktap_totals

