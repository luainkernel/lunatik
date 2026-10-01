#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A thread's __close is its stop, and a to-be-closed variable holding a thread
# stops it at the end of its scope.
#
# stop.lua is spawned, since thread.run is refused while a script loads. It
# threads a runtime whose body returns at once, so no failure leaves a thread
# running, and finds one function under both __close and stop in the thread's
# metatable: a thread is shared, and the monitor leaves a stop unwrapped as it
# does a close, so the two names hold the same entry. A to-be-closed variable
# holding the thread then goes out of scope, and the task the thread reports
# afterwards is gone, as after a stop; a second stop does nothing. A build
# without the __close fails at the to-be-closed variable, which Lua refuses for
# a value with no __close, and one whose monitor still wraps the stop fails the
# comparison.
#
# Usage: sudo bash tests/thread/stop.sh

SCRIPT="tests/thread/stop"
PREFIX="thread stop test: "
TRIES=50

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

reported()
{
	dmesg_since | grep -qF "$PREFIX$1"
}

awaited()
{
	for _ in $(seq $TRIES); do
		reported "$1" && return
		sleep 0.1
	done
}

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
awaited "closed"
lunatik stop "$SCRIPT" > /dev/null 2>&1

reported "closed" || fail "a to-be-closed thread was not stopped, or its __close is not its stop"
ktap_pass "a to-be-closed variable stops a thread, through the stop it holds as __close"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

