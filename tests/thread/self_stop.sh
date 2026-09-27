#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# thread:stop() from under the lock of the thread's runtime is refused, and
# accepted off it.
#
# A thread's body runs under its runtime's lock, and a stop waits for the body:
# from under that lock it waits on itself, whether it comes from the thread's
# own body or from another task, while the thread waits for that lock or has
# not run yet. self_stop.lua is spawned, since a thread is started from a
# thread: it threads self_stop_body, whose body yields, and resumes that
# runtime with the thread object, whose stop from the resumed body is refused;
# the driver then stops the thread from its own body, off the lock, which is
# accepted. self_stop_self is spawned next, and its body stops its own script
# through runner.stop, which stops the thread first and is refused; the
# command line then stops it, which is accepted. A build without the refusal
# accepts the first stop without hanging, since that thread has already
# returned, and fails there; the self stop, which such a build would wait on
# forever, runs only after the first case saw the refusal.
#
# Usage: sudo bash tests/thread/self_stop.sh

SCRIPT="tests/thread/self_stop"
SELF="tests/thread/self_stop_self"
REFUSAL="not allowed from the runtime itself"
TRIES=50

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$SELF" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

reported()
{
	dmesg_since | grep -cF "thread self_stop test: $1"
}

awaited()
{
	for _ in $(seq $TRIES); do
		[ "$(reported "$1")" = 1 ] && return
		sleep 0.1
	done
}

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
awaited "driver stop"
lunatik stop "$SCRIPT" > /dev/null 2>&1
[ "$(reported "resumed stop $REFUSAL")" = 1 ] || fail "a thread stop from a resumed body of its runtime was not refused"
ktap_pass "a thread stop from a resumed body of its runtime is refused"

output=$(lunatik spawn "$SELF" 2>&1)
[ -z "$output" ] || fail "$output"
awaited "self stop"
[ "$(reported "self stop $REFUSAL")" = 1 ] || fail "a thread stop from its own body was not refused"
ktap_pass "a thread stop from its own body is refused"

[ "$(reported "driver stop accepted")" = 1 ] || fail "a thread stop from the driver's body, off the lock, was refused"
output=$(lunatik stop "$SELF" 2>&1)
[ -z "$output" ] || fail "a thread stop from the command line was refused: $output"
ktap_pass "a thread stop off its runtime's lock is accepted"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

