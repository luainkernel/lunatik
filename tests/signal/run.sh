#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the signal tests and reports KTAP results.
#
# signal/mask: sigmask blocks and unblocks a signal for the task that runs the
# script, and sigstate reads it back as blocked, allowed and not pending; a
# signal of 0 or past the set, and a command past SIG_UNBLOCK, raise "out of
# bounds" instead of reaching sigaddset, whose shift is undefined there.
#
# signal/kill: with a child sleeping in the background and a pid the shell has
# already reaped, kill(child, 0) probes the child, kill(reaped) raises ESRCH,
# a pid of 0, one past PID_MAX_LIMIT and one that would truncate to the
# child's, and a signal that would truncate to TERM, raise "out of bounds", and
# kill(child, TERM) returns true; the shell then sees the child end on SIGTERM.
# The truncation cases target the child on every build, so a module without
# the bound sends the child a signal and fails the case, never a stranger.
#
# Usage: sudo bash tests/signal/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
SCRIPT_MASK="tests/signal/mask"
SCRIPT_KILL="tests/signal/kill"
PIDMOD="/lib/modules/lua/tests/signal/pids.lua"

source "$DIR/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT_MASK" 2>/dev/null
	lunatik stop "$SCRIPT_KILL" 2>/dev/null
	rm -f "$PIDMOD"
	[ -n "${CHILD:-}" ] && kill -KILL "$CHILD" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

if run_test "$SCRIPT_MASK"; then
	ktap_pass "signal/mask"
else
	ktap_fail "signal/mask"
fi

sleep 30 &
CHILD=$!
true &
REAPED=$!
wait "$REAPED"
echo "return {child = $CHILD, reaped = $REAPED}" > "$PIDMOD"

if run_test "$SCRIPT_KILL"; then
	ktap_pass "signal/kill"
else
	ktap_fail "signal/kill"
fi

wait "$CHILD"
status=$?
CHILD=
if [ "$status" -eq 143 ]; then
	ktap_pass "signal/kill: the child ends on SIGTERM"
else
	ktap_fail "signal/kill: the child ended with status $status, not 143"
fi

ktap_totals

