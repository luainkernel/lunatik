#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# runtime:stop(), and the __close of a runtime, from inside a netdevice callback
# are refused, and a stop is accepted once the callback returned.
#
# The close a stop runs collects every object of the state on the calling task,
# and a netdevice block's release calls unregister_netdevice_notifier, which
# takes the namespace rwsem for write and RTNL; the callback runs on the task
# that holds RTNL. stop.lua starts a child runtime whose block reports the UP
# and the DOWN of one device, registers its own block after it, and asks to
# stop the child from its callback, through stop() and through a <close> local
# going out of scope, in both the contexts the callback runs in: the replay the
# registration delivers on its own task, and the UP of that device, a live
# event on another task. All four are refused with the message the test
# asserts, and the child's block still reports the DOWN that follows. A percpu
# set is stopped and closed from the same callbacks, refused the same way, and
# stopped from the script body afterwards, where it is accepted; so is a runtime
# that holds no block, stopped off RTNL. Stopping the script and the child
# leaves the module's use count as it found it.
#
# The child's block holds its runtime, so a child the script alone held would
# outlive it. The script starts the child through the runner instead, and the
# cleanup stops it by name.
#
# A tree without the refusal does not fail this test, it wedges the host: the
# unregistration waits on the locks the callback's own task holds, and that task
# stays in D state with both. So this test runs only on a tree that carries the
# refusal, and discriminates by the message it asserts. The loaded build is not
# always the installed one, so before it creates anything the test looks for the
# runtime's stop, which carries the refusal, in /proc/kallsyms, and skips when
# the loaded lunatik does not have it. The percpu's refusal has no symbol of its
# own: the set holds runtimes without a block, whose close takes no RTNL, so a
# build that lacks it accepts the stop rather than wedging, and the message
# discriminates.
#
# Usage: sudo bash tests/notifier/stop.sh

SCRIPT="tests/notifier/stop"
CHILD="tests/notifier/stop_child"
MODULE="luanotifier"
REFUSING="lunatik_lstop"
DEVICE="stop0"
REFUSAL="not allowed under RTNL"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHILD" > /dev/null 2>&1
	ip link del "$DEVICE" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 8

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "a stop from the replay callback is refused"
	ktap_skip "a stop from a live callback is refused"
	ktap_skip "a close from either callback is refused"
	ktap_skip "the child it would have stopped keeps delivering"
	ktap_skip "a stop once the callback returned is accepted"
	ktap_skip "a percpu's stop and close from either callback are refused, and accepted once it returned"
	ktap_skip "the module's use count is left as it was"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "notifier stop test: $1"
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
before=$(cat /sys/module/$MODULE/refcnt 2> /dev/null) || skip_all "$MODULE not loaded"
grep -Eq " $REFUSING[[:space:]]\[lunatik\]$" /proc/kallsyms 2> /dev/null ||
	skip_all "no $REFUSING in the loaded lunatik: it cannot refuse a stop under RTNL"

mark_dmesg
run_script "$SCRIPT"

ip link add "$DEVICE" type dummy || fail "cannot create $DEVICE"
ip link set "$DEVICE" up || fail "cannot bring $DEVICE up"
ip link set "$DEVICE" down || fail "cannot bring $DEVICE down"

lunatik stop "$SCRIPT"
lunatik stop "$CHILD"
after=$(cat /sys/module/$MODULE/refcnt 2> /dev/null)
ip link del "$DEVICE"

[ "$(reported "replay stop $REFUSAL")" = 1 ] || fail "a stop from the replayed callback was not refused"
ktap_pass "a stop from the replay callback is refused"

[ "$(reported "live stop $REFUSAL")" = 1 ] || fail "a stop from a live callback was not refused"
ktap_pass "a stop from a live callback is refused"

[ "$(reported "replay close $REFUSAL")" = 1 ] || fail "a close from the replayed callback was not refused"
[ "$(reported "live close $REFUSAL")" = 1 ] || fail "a close from a live callback was not refused"
ktap_pass "a close from either callback is refused"

[ "$(reported "child up $DEVICE")" = 1 ] || fail "the child's block did not report the UP"
[ "$(reported "child down $DEVICE")" = 1 ] || fail "the child's block did not report the DOWN after the refused stop"
ktap_pass "the child it would have stopped keeps delivering"

[ "$(reported "after stop accepted")" = 1 ] || fail "a stop made after the callbacks returned was refused"
ktap_pass "a stop once the callback returned is accepted"

[ "$(reported "replay percpu stop $REFUSAL")" = 1 ] || fail "a percpu stop from the replayed callback was not refused"
[ "$(reported "live percpu stop $REFUSAL")" = 1 ] || fail "a percpu stop from a live callback was not refused"
[ "$(reported "replay percpu close $REFUSAL")" = 1 ] || fail "a percpu close from the replayed callback was not refused"
[ "$(reported "live percpu close $REFUSAL")" = 1 ] || fail "a percpu close from a live callback was not refused"
[ "$(reported "after percpu stop accepted")" = 1 ] || fail "a percpu stop made after the callbacks returned was refused"
ktap_pass "a percpu's stop and close from either callback are refused, and accepted once it returned"

[ "$after" = "$before" ] || fail "$MODULE use count went from $before to $after"
ktap_pass "the module's use count is left as it was"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

