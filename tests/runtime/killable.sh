#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A wait on a runtime's lock that a script starts ends when its kernel thread is
# stopped or its task takes a fatal signal.
#
# killable_holder is spawned: its body holds its runtime's lock, and resumes a
# percpu set whose first runtime sleeps under its own lock. killable_waiter is
# spawned next and waits on those locks through runtime:resume; the command line
# stops it, and each entry that takes such a lock, resume, thread.run, stop and
# the set's resume and stop, leaves with EINTR. A read of lunatik_killable, a
# device of killable_device, resumes the holder's runtime and waits; kill -9
# ends the read with EINTR. killable_blocked is then spawned and resumes the
# devices' runtime in a loop, and a read of lunatik_killable_stop, which holds
# that runtime's lock, stops the thread waiting on it, which returns. The test
# skips unless the loaded core carries lunatik_closekillable, the symbol only
# the fixed build has, since a build whose waits ignore a stop would wait
# forever on the stop from under the lock; that stop also runs only after the
# first two cases passed, which such a build fails once the holder lets go,
# ten seconds on.
#
# Usage: sudo bash tests/runtime/killable.sh

HOLDER="tests/runtime/killable_holder"
WAITER="tests/runtime/killable_waiter"
DEVICE="tests/runtime/killable_device"
BLOCKED="tests/runtime/killable_blocked"
NODE="/dev/lunatik_killable"
MODULE="lunatik"
FIX="lunatik_closekillable"
TRIES=50
SETTLE=0.5

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$BLOCKED" > /dev/null 2>&1
	lunatik stop "$WAITER" > /dev/null 2>&1
	lunatik stop "$DEVICE" > /dev/null 2>&1
	lunatik stop "$HOLDER" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
grep -qw "$FIX" /proc/kallsyms || {
	echo "# SKIP: the loaded $MODULE does not carry $FIX: the stop from under the lock would wait forever"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "killable test: $1"
}

awaited()
{
	for _ in $(seq $TRIES); do
		[ "$(reported "$1")" -ge 1 ] && return
		sleep 0.1
	done
}

mark_dmesg
output=$(lunatik spawn "$HOLDER" 2>&1)
[ -z "$output" ] || fail "$output"
awaited "held"
[ "$(reported "held")" = 1 ] || fail "the holder did not take the locks"

output=$(lunatik spawn "$WAITER" 2>&1)
[ -z "$output" ] || fail "$output"
sleep $SETTLE
lunatik stop "$WAITER" > /dev/null 2>&1
for entry in "resume" "run" "stop" "percpu resume" "percpu stop"; do
	[ "$(reported "thread $entry EINTR")" = 1 ] || fail "a stopped thread's $entry did not leave its wait"
done
ktap_pass "a stopped thread leaves its wait on a runtime's lock in resume, thread.run, stop and a set's resume and stop"

run_script "$DEVICE"
cat "$NODE" > /dev/null 2>&1 &
reader=$!
sleep $SETTLE
kill -9 $reader
wait $reader 2> /dev/null
awaited "fop resume"
[ "$(reported "fop resume EINTR")" = 1 ] || fail "a killed reader did not leave its wait on a runtime's lock"
ktap_pass "a killed task leaves its wait on a runtime's lock"

output=$(lunatik spawn "$BLOCKED" 2>&1)
[ -z "$output" ] || fail "$output"
cat "${NODE}_stop" > /dev/null 2>&1
[ "$(reported "fop stop accepted")" = 1 ] || fail "a thread waiting on a runtime's lock was not stopped from under it"
ktap_pass "a thread waiting on a runtime's lock is stopped from under that lock"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

