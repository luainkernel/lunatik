#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A thread's __close is its stop, a to-be-closed variable holding a thread
# stops it at the end of its scope, the stop says whether the body raised, and
# a stop of a thread another stop holds returns at once.
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
# comparison. The stop of a thread whose body returns at once returns true,
# whether the body ran or the stop came first, and so does a second stop of it;
# the stop of a thread whose body raised returns false, made once the body told
# the driver it runs, so the stop does not land before it. Last, a body leaves a
# sentinel in its runtime whose finalizer stops the thread through a table the
# driver stored it in; the driver drops the runtime's handle, so its stop closes
# that runtime, and the stop the finalizer makes from there returns true. A
# build that closes the runtime under the thread's lock leaves that stop
# waiting on a lock its own task holds, until the driver's stop interrupts it,
# and a build whose monitor wraps the stop refuses it: the case fails on both.
# Then a body that outlasts its stop: once it sees the stop it tells the
# driver, and sleeps uninterruptibly, since the stop's signal ends an
# interruptible sleep at once, until the driver releases it or three seconds
# pass; it waits for the stop no longer, so a failure before the stop leaves no
# thread running. A second thread stops it, and the driver, told the body sees
# that stop, reads the thread's task and stops the thread again while the first
# stop waits: the task object has no task, the second stop returns true, the
# body is released before its bound, and the first stop returns true, which it
# does once the thread has exited. A build that holds the thread's lock across
# kthread_stop keeps the driver's read waiting until the body's bound passes,
# so the case fails without a wedge.
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
ktap_plan 6

reported()
{
	dmesg_since | grep -qE "$PREFIX$1\$"
}

# verdict <case> <description>: each case reports its name once it passed, or its error
verdict()
{
	if reported "$1"; then
		ktap_pass "$2"
	else
		ktap_fail "$2"
	fi
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
awaited "concurrent"
lunatik stop "$SCRIPT" > /dev/null 2>&1

verdict "closed" "a to-be-closed variable stops a thread, through the stop it holds as __close"
verdict "returned" "stop returns true when the body did not raise, and on a thread already stopped"
verdict "raised" "stop returns false when the body raised"
verdict "finalized" "a stop from a finalizer of the runtime the stop closes returns true"
verdict "concurrent" "a stop of a thread another stop holds returns true at once, and task reads no task"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

