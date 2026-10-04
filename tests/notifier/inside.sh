#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Where notifier.netdevice may register: a softirq runtime's body, outside a
# netdevice callback, and nowhere else.
#
# A netdevice callback runs under RTNL, so nothing it reaches may wait on RTNL,
# and a softirq runtime takes no call that sleeps once armed: a process runtime is
# refused. register_netdevice_notifier takes the namespace rwsem for write and
# RTNL, and the chain is called under RTNL, so a registration made from a callback
# waits on a lock its own task already holds. inside.lua asks for one in both the
# contexts the callback runs in: the replay the registration delivers on its own
# task, while the body has not armed the runtime, and a live event on another task.
# It asks again from a coroutine resumed inside the callback, and once more after
# the callbacks returned, where it is accepted; from the replay it also asks
# linux.schedule to sleep, which lunatik_checkarmed refuses under RTNL as it refuses
# every entry point that may sleep, though the body has not armed the runtime; a third one raises from its replay,
# with no position in its message, so that last registration reads the task
# cleared on the dispatcher's error path as well. And it stops a second notifier
# from inside that notifier's own callback, which makes no kernel call and stays
# legal. Stopping the script leaves the module's use count as it found it.
#
# A tree without the guard does not fail this test, it wedges the host: the
# registration from the replay waits on the two locks the callback's own task
# holds and the task stays in D state with both, which no stop clears. So this
# test runs only on a tree that carries the guard and discriminates by the message
# it asserts, never by an A/B. The accepted registration is what pins the task
# being cleared, on the path where the callback returns and on the one where it
# raises; the coroutine is what pins the refusal keyed on the task rather than on
# one Lua state. The loaded build is not always the installed one, so before it
# creates anything the test looks for the dispatch that sets the task, the
# netdevice call, in /proc/kallsyms, and skips when the loaded module does not
# have it.
#
# Usage: sudo bash tests/notifier/inside.sh

SCRIPT="tests/notifier/inside"
PROCESS="tests/notifier/inside_process"
MODULE="luanotifier"
DISPATCH="luanotifier_netdevice_call"
OLDDEV="inside0"
NEWDEV="inside1"
REFUSAL="not allowed under RTNL"
MISMATCH="runtime context mismatch: notifier needs softirq"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$PROCESS" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ip link del "$OLDDEV" 2> /dev/null
	ip link del "$NEWDEV" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 9

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "a process runtime is refused"
	ktap_skip "a registration from the replay callback is refused"
	ktap_skip "a coroutine resumed from the callback is refused too"
	ktap_skip "a call that sleeps from the replay callback is refused"
	ktap_skip "a registration after a callback returned, and after one that raised, is allowed"
	ktap_skip "a registration from a live callback is refused"
	ktap_skip "stop() from inside the callback is allowed and ends delivery"
	ktap_skip "the module's use count is left as it was"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "notifier inside test: $1"
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
before=$(cat /sys/module/$MODULE/refcnt 2> /dev/null) || skip_all "$MODULE not loaded"
grep -Eq " $DISPATCH[[:space:]]\[$MODULE\]$" /proc/kallsyms 2> /dev/null ||
	skip_all "no $DISPATCH in the loaded $MODULE: it cannot refuse under RTNL"
ip link add "$OLDDEV" type dummy 2> /dev/null || skip_all "cannot create a dummy device"

mark_dmesg
output=$(lunatik run "$PROCESS" 2>&1)
echo "$output" | grep -qF "$MISMATCH" || fail "a process runtime registered: ${output:-no error}"
ktap_pass "a process runtime is refused"

run_script --context=softirq "$SCRIPT"

[ "$(reported "replay $REFUSAL")" = 1 ] || fail "a registration from the replayed callback was not refused"
ktap_pass "a registration from the replay callback is refused"

[ "$(reported "coroutine $REFUSAL")" = 1 ] || fail "a registration from a coroutine of the callback was not refused"
ktap_pass "a coroutine resumed from the callback is refused too"

[ "$(reported "schedule $REFUSAL")" = 1 ] || fail "a call that sleeps from the replayed callback was not refused"
ktap_pass "a call that sleeps from the replay callback is refused"

raised=$(reported raised)
[ "$raised" = 1 ] || fail "the callback that raises ran $raised times, expected 1"
[ "$(reported "after accepted")" = 1 ] || fail "a registration made after the callbacks returned was refused"
ktap_pass "a registration after a callback returned, and after one that raised, is allowed"

ip link add "$NEWDEV" type dummy || fail "cannot create $NEWDEV"
ip link set "$NEWDEV" up || fail "cannot bring $NEWDEV up"

[ "$(reported "live $REFUSAL")" = 1 ] || fail "a registration from a live callback was not refused"
ktap_pass "a registration from a live callback is refused"

stopped=$(reported stop)
[ "$stopped" = 1 ] || fail "the callback that stops its own notifier ran $stopped times, expected 1"
ktap_pass "stop() from inside the callback is allowed and ends delivery"

lunatik stop "$SCRIPT"
after=$(cat /sys/module/$MODULE/refcnt 2> /dev/null)
[ "$after" = "$before" ] || fail "$MODULE use count went from $before to $after"
ktap_pass "the module's use count is left as it was"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

