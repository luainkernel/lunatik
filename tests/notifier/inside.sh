#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A netdevice callback runs on a kernel worker, off RTNL, so what takes RTNL
# is accepted inside it, on the replay and on a live event alike.
#
# register_netdevice_notifier takes the namespace rwsem for write and RTNL, and
# unregister_netdevice_notifier takes both again, while the chain is called
# under RTNL. inside.lua registers three blocks. From the first callback of the
# first block's replay, and from its first callback for a live device, it
# registers a notifier and stops it, lists the links through netlink.rt, a dump
# rtnetlink runs under RTNL, creates a generic netlink family and stops it,
# which takes the lock a generic netlink request holds while it waits on RTNL,
# creates a runtime whose body registers a notifier and stops that runtime, and
# resumes a runtime whose resumed function registers one and stops that runtime
# too: each registration takes RTNL, and each stop of a runtime that holds a
# block unregisters it. The second block stops itself from its first callback
# and is not called again. The third raises from its first callback, which is
# logged, and its next callback still runs.
#
# A build that runs the callback under RTNL wedges the host rather than failing
# this test: a registration from the callback waits on the locks its own task
# holds. So the test runs only on a build that defers the callback, and skips
# unless the loaded luanotifier lists luanotifier_drain in /proc/kallsyms. Every
# runtime it creates is stopped where it is created, so stopping the script
# leaves luanotifier's use count as it was, once the releases the workers run
# have run.
#
# Usage: sudo bash tests/notifier/inside.sh

SCRIPT="tests/notifier/inside"
MODULE="luanotifier"
DRAIN="luanotifier_drain"
LIVEDEV="inside1"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ip link del "$LIVEDEV" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 8

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "a registration, a netlink.rt request and a family from the replayed callback are accepted"
	ktap_skip "a runtime the replayed callback creates or resumes registers, and is stopped there"
	ktap_skip "a registration, a netlink.rt request and a family from a live callback are accepted"
	ktap_skip "a runtime a live callback creates or resumes registers, and is stopped there"
	ktap_skip "stop() from inside the callback ends delivery"
	ktap_skip "a callback that raised is logged, and its next event still reaches it"
	ktap_skip "the module's use count is left as it was"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "notifier inside test: $1"
}

reports()
{
	[ "$(reported "$1")" = 1 ]
}

released()
{
	[ "$(cat /sys/module/$MODULE/refcnt 2> /dev/null)" = "$before" ]
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
before=$(cat /sys/module/$MODULE/refcnt 2> /dev/null) || skip_all "$MODULE not loaded"
grep -Eq " $DRAIN[[:space:]]\[$MODULE\]$" /proc/kallsyms 2> /dev/null ||
	skip_all "no $DRAIN in the loaded $MODULE: it runs the callback under RTNL"

mark_dmesg
run_script "$SCRIPT"

awaited reports "replay family accepted" || fail "a family from the replayed callback was not accepted"
reports "replay register accepted" || fail "a registration from the replayed callback was not accepted"
reports "replay request accepted" || fail "a netlink.rt request from the replayed callback was not accepted"
ktap_pass "a registration, a netlink.rt request and a family from the replayed callback are accepted"

awaited reports "replay resume accepted" || fail "a runtime the replayed callback resumes did not register"
reports "replay runtime accepted" || fail "a runtime the replayed callback creates did not register"
ktap_pass "a runtime the replayed callback creates or resumes registers, and is stopped there"

ip link add "$LIVEDEV" type dummy || fail "cannot create $LIVEDEV"

awaited reports "live family accepted" || fail "a family from a live callback was not accepted"
reports "live register accepted" || fail "a registration from a live callback was not accepted"
reports "live request accepted" || fail "a netlink.rt request from a live callback was not accepted"
ktap_pass "a registration, a netlink.rt request and a family from a live callback are accepted"

awaited reports "live resume accepted" || fail "a runtime a live callback resumes did not register"
reports "live runtime accepted" || fail "a runtime a live callback creates did not register"
ktap_pass "a runtime a live callback creates or resumes registers, and is stopped there"

stopped=$(reported stop)
[ "$stopped" = 1 ] || fail "the callback that stops its own notifier ran $stopped times, expected 1"
ktap_pass "stop() from inside the callback ends delivery"

raised=$(reported raised)
[ "$raised" = 1 ] || fail "the callback that raises ran $raised times, expected 1"
awaited reports "delivered after a raise" || fail "the callback that raised was not called again"
ktap_pass "a callback that raised is logged, and its next event still reaches it"

lunatik stop "$SCRIPT"
awaited released || fail "$MODULE use count went from $before to $(cat /sys/module/$MODULE/refcnt 2> /dev/null)"
ktap_pass "the module's use count is left as it was"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

