#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the objects thread.run() passes to the thread body.
#
# The driver is spawned, since thread.run() is refused while a script loads.
# It runs a body script with a fifo and a control block, and waits for the
# marker the body pushes through the fifo once it reads the token the driver
# left in the control block, pinning the order in which the two objects
# arrive. Before that it takes the three refusals:
# a number where an object is expected ("invalid object") and a SINGLE object
# ("cannot share SINGLE object"), neither of which reaches the runtime, as the
# run that follows proves; and a runtime already stopped ("stopped runtime").
#
# A second run carries more objects than the LUA_MINSTACK slots a C function is
# entered with, sized 1 to 32 so the body sees them in order, which is a copy
# longer than the stack the copy is given.
#
# Usage: sudo bash tests/thread/run_args.sh

SCRIPT="tests/thread/run_args"
SLEEP=2

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -n "$output" ] && fail "$output"
sleep $SLEEP
lunatik stop "$SCRIPT"

check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -q "run_args: PASS" || fail "the thread body did not get the objects given to thread.run()"
ktap_pass "thread.run() passes its objects to the thread body and refuses what cannot cross"

ktap_totals

