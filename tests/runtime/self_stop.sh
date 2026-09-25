#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A runtime is not stopped, resumed, threaded or dispatched to from under its
# own lock.
#
# A callback, a device file operation, a thread body or a resumed body runs
# under the runtime's lock, and the close a stop runs, a resume and the
# arguments thread.run passes take that lock: each waits on the task that holds
# it. self_stop.lua creates a child and resumes it with its own handle, and a
# percpu set of the same child resumed with its own, and each calls stop() and
# resume() on itself from the resumed body, the runtime thread.run on itself
# too, and reports the refusals; the driver then stops both from its body, off
# the lock, and reports the stops accepted. It also creates lunatik_self_stop,
# whose read stops, resumes and threads the driver's own runtime, reached
# through the runner's registry, and reports the same refusals, then opens its
# own node through io.open, which fails, since a file operation dispatched on
# the task that holds the runtime's lock answers EDEADLK instead of taking it,
# and opens the node of a device another runtime made, self_stop_other's, which
# is accepted: the same open, on a lock this task does not hold. The kernel's
# io library hands the script no errno, so the case reads the refusal and not
# its name. A build without the checks does not fail these cases, it wedges the
# host on the lock its own task holds, so the test skips unless the loaded core
# is the installed one and that file carries the refusal: the checks are
# inline, so no symbol of theirs is in /proc/kallsyms, and the message is what
# the installed lunatik.ko has.
#
# Usage: sudo bash tests/runtime/self_stop.sh

SCRIPT="tests/runtime/self_stop"
OTHER="tests/runtime/self_stop_other"
DEVICE="lunatik_self_stop"
MODULE="lunatik"
REFUSAL="not allowed from the runtime itself"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$OTHER" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
[ "$(cat /sys/module/$MODULE/srcversion)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] || {
	echo "# SKIP: the loaded $MODULE is not the installed one: a self stop would wait on its own lock"
	ktap_totals
	exit 0
}
grep -qaF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)" || {
	echo "# SKIP: the installed $MODULE does not carry the refusal: a self stop would wait on its own lock"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "self_stop test: $1"
}

mark_dmesg
run_script "$SCRIPT"

for entry in stop resume thread; do
	[ "$(reported "self $entry $REFUSAL")" = 1 ] || fail "a resumed body's $entry on its own runtime was not refused"
	[ "$(reported "self $entry accepted")" = 0 ] || fail "a resumed body's $entry on its own runtime was accepted"
done
for entry in stop resume; do
	refused=$(reported "percpu self $entry $REFUSAL")
	[ "$refused" -ge 1 ] || fail "a resumed body's $entry on its own percpu set was not refused"
	[ "$(reported "percpu self $entry ")" = "$refused" ] || fail "a resumed body's $entry on its own percpu set was accepted, or refused for another reason"
done
[ "$(reported "body stop accepted")" = 2 ] || fail "a stop from the driver's body, off the lock, was refused"
ktap_pass "a runtime and a percpu set refuse a stop, a resume and a thread from a resumed body and accept a stop from the driver's body"

cat "/dev/$DEVICE" > /dev/null 2>&1
for entry in stop resume thread; do
	[ "$(reported "fop $entry $REFUSAL")" = 1 ] || fail "a device read's $entry on its own runtime was not refused"
done
[ "$(reported "fop open own refused")" = 1 ] || fail "a device read opened its own node"
[ "$(reported "fop open other accepted")" = 1 ] || fail "a device read could not open another runtime's node"
ktap_pass "a device's read is refused a stop, a resume and a thread on its own runtime, cannot open its own node and opens another runtime's"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

