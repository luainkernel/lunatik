#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for what runtime:resume leaves behind: a resumed script hands
# the function it returns to the next resumption, which is how thread.run gets a
# thread body, as the echod example does. A resume that consumed that value
# would return it to the caller and leave the thread with nothing to run.
#
# Usage: sudo bash tests/runtime/resume_thread.sh

SCRIPT="tests/runtime/resume_thread"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -n "$output" ] && fail "Lua error while spawning: $output"
sleep 2
lunatik stop "$SCRIPT" > /dev/null 2>&1
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -qF "resume_thread: PASS" || \
	fail "$(dmesg_since | grep -o 'resume_thread: FAIL.*' | head -1)"
ktap_pass "a resumed script hands its thread body to thread.run"

ktap_totals

