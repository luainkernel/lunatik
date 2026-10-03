#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the signal tests and reports KTAP results.
#
# signal/kill: with a child sleeping in the background and a pid the shell has
# already reaped, kill(child, 0) finds the child and answers true,
# kill(reaped, 0) answers nil and ESRCH, a pid of 0, one past PID_MAX_LIMIT and
# one that would truncate to the child's, and a signal that would truncate to
# TERM, raise "out of bounds", and kill(child, TERM) answers true and signals
# the child, and the shell then sees the child end on SIGTERM.
# The truncation cases target the child on every build, so a module without
# the bound sends the child a signal and fails the case, never a stranger.
#
# Before that last kill, a softirq runtime's callback, which runs with IRQs on,
# sends the child CONT twice and both answer true, in place, and a hardirq
# runtime's callback, which runs with IRQs off, sends a second child TERM and
# that defers it: the call answers true, a second TERM answers false while its
# CPU holds the first, kill(second, 0) answers true at the call, and the reaped
# pid answers nil and ESRCH there. The shell then sees the second child end on
# the deferred SIGTERM. Once the worker has sent it, a hardirq runtime's callback
# on the same CPU, to which the CLI is pinned, defers CONT to the child: the
# script retries it for a second while the CPU still holds the TERM, and a build
# whose worker leaves the CPU's slot taken fails there. A build that sends in
# place with IRQs off answers the second TERM true, and one that defers with
# IRQs on answers the softirq's second CONT false; neither holds a siglock or a
# runqueue lock the callback's CPU holds, so neither wedges the host.
#
# The script runs from a CLI in a pid namespace of its own, which holds neither
# pid: kill reads a pid in the initial pid namespace, as task:pid() returns it,
# whichever task makes the call, and a module that reads it in the caller's
# answers ESRCH for the child and fails both cases. The shell has to run in the
# initial pid namespace, the only one whose pids are the ones kill reads, and
# the cases skip elsewhere, without pid namespaces or without taskset.
#
# Usage: sudo bash tests/signal/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
SCRIPT_KILL="tests/signal/kill"
PIDMOD="/lib/modules/lua/tests/signal/pids.lua"

source "$DIR/../lib.sh"

# the CLI in a pid namespace of its own, on CPU 0, where every deferral of the script takes one slot
pinned() { taskset -c 0 unshare --pid --fork lunatik "$@"; }

cleanup() {
	lunatik stop "$SCRIPT_KILL" 2>/dev/null
	rm -f "$PIDMOD"
	[ -n "${CHILD:-}" ] && kill -KILL "$CHILD" 2>/dev/null
	[ -n "${DEFERRED:-}" ] && kill -KILL "$DEFERRED" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

if ! initpidns || ! unshare --pid --fork true 2>/dev/null || ! command -v taskset > /dev/null 2>&1; then
	ktap_skip "signal/kill: needs to run in the initial pid namespace, to create another and taskset"
	ktap_skip "signal/kill: the child ends on SIGTERM"
	ktap_skip "signal/kill: the second child ends on the deferred SIGTERM"
	ktap_totals
	exit 0
fi

sleep 30 &
CHILD=$!
sleep 30 &
DEFERRED=$!
true &
REAPED=$!
wait "$REAPED"
echo "return {child = $CHILD, deferred = $DEFERRED, reaped = $REAPED}" > "$PIDMOD"

if CLI=pinned run_test "$SCRIPT_KILL"; then
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

wait "$DEFERRED"
status=$?
DEFERRED=
if [ "$status" -eq 143 ]; then
	ktap_pass "signal/kill: the second child ends on the deferred SIGTERM"
else
	ktap_fail "signal/kill: the second child ended with status $status, not 143"
fi
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

