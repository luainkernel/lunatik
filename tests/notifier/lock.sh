#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What a task that holds the lock of a runtime with a netdevice notifier is
# refused, in whatever runtime its Lua runs, on a task that does not hold RTNL,
# and what it still does.
#
# The netdevice chain runs under RTNL and takes the runtime's lock, so Lua on a
# task that holds that lock and waits on RTNL, or on a lock a request holds while
# it waits on RTNL, closes a cycle with any netdevice event. lock_holder.lua
# registers a notifier from its body and returns a function that probes;
# lock.lua resumes it from another runtime, where it runs under the holder's
# lock on the CLI's task, and the test then spawns the holder, where it runs as
# a thread body. In the resumed body a netlink receive and request, a second
# registration, a netlink.channel, a generic netlink group bind, an option past
# SOL_SOCKET, an AF_PACKET close and the stop of a runtime and of a percpu set
# are refused with the message the test asserts, as is a receive from a
# coroutine made before the registration, and a receive once the notifier is
# stopped, whose block stays in the chain until the runtime closes. A helper
# runtime the resumed body creates runs its own body there, under the holder's
# lock, and its code again once that body resumes it: a receive and a request
# from each are refused, which pins the refusal on the task that holds the lock
# and not on the runtime whose Lua makes the call. A SOL_SOCKET option, a UDP
# send and a UDP close take no RTNL and are accepted there. The script body runs
# off the lock, so a request from it after the registration is accepted, and so
# are the stops the finalizers of the holder's close run, the helper's among
# them. The thread body is refused the same.
#
# A build without the refusal takes RTNL under the holder's lock, which wedges
# the host only if a netdevice event arrives in that window. The test does not
# rule that out on a host it does not own, so it skips unless every module the
# probes reach is the installed one and the installed file carries the refusal,
# and the loaded core has the scan of the runtimes the chain locks,
# lunatik_blocksrtnl; the holder and the helper make the probes that take RTNL
# only once a receive, which cannot wedge, was refused.
#
# Usage: sudo bash tests/notifier/lock.sh

SCRIPT="tests/notifier/lock"
HOLDER="tests/notifier/lock_holder"
MODULE="luanotifier"
MODULES="lunatik luanotifier luasocket luanetlink"
SCAN="lunatik_blocksrtnl"
REFUSAL="not allowed under the lock of a runtime with a netdevice notifier"
TRIES=50

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$HOLDER" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 15

skip_all()
{
	echo "# SKIP: $1"
	ktap_totals
	exit 0
}

for module in $MODULES; do
	[ -r /sys/module/$module/srcversion ] || skip_all "$module not loaded"
	[ "$(cat /sys/module/$module/srcversion)" = "$(modinfo -F srcversion $module 2> /dev/null)" ] ||
		skip_all "the loaded $module is not the installed one"
	grep -aqF "$REFUSAL" "$(modinfo -n $module 2> /dev/null)" 2> /dev/null ||
		skip_all "the installed $module does not refuse under the lock of a runtime with a netdevice notifier"
done
grep -Eq " $SCAN[[:space:]]\[lunatik\]$" /proc/kallsyms 2> /dev/null ||
	skip_all "no $SCAN in the loaded lunatik: it cannot refuse on the task"
[ -e /proc/net/packet ] || modinfo af_packet > /dev/null 2>&1 || skip_all "no AF_PACKET support"

reported()
{
	dmesg_since | grep -cF "notifier lock test: $1"
}

refused()
{
	local probe
	for probe in "$@"; do
		[ "$(reported "$probe $REFUSAL")" = 1 ] || fail "$probe was not refused under the lock of a runtime with a netdevice notifier"
	done
}

accepted()
{
	local probe
	for probe in "$@"; do
		[ "$(reported "$probe accepted")" = 1 ] || fail "$probe was refused"
	done
}

before=$(cat /sys/module/$MODULE/refcnt)

mark_dmesg
run_script "$SCRIPT"

refused receive
ktap_pass "a netlink receive from a resumed body of a runtime with a netdevice notifier is refused"

refused "coroutine receive"
ktap_pass "a coroutine made before the registration is refused there too"

refused request registration channel
ktap_pass "a netlink request, a netdevice registration and a netlink.channel are refused there"

refused bind "protocol option" "packet close"
ktap_pass "a generic netlink group bind, an option past SOL_SOCKET and an AF_PACKET close are refused there"

refused stop "percpu stop"
ktap_pass "the stop of a runtime and of a percpu set are refused there"

accepted "socket option" send close
ktap_pass "a SOL_SOCKET option, a UDP send and a UDP close are accepted there"

accepted nest
refused "helper body receive" "helper body request" "helper resume receive" "helper resume request"
ktap_pass "a runtime created and resumed there is refused in its body and in its code"

refused "stopped receive"
ktap_pass "a stopped notifier's runtime still refuses"

accepted "body request"
ktap_pass "a request from the script body after the registration is accepted"

accepted "close stop" "close percpu stop" "close helper stop"
ktap_pass "the finalizers the runtime's close runs stop the runtimes"

check_dmesg && ktap_pass "no Lua errors in kernel from the resumed body"

mark_dmesg
output=$(lunatik spawn "$HOLDER" 2>&1)
[ -z "$output" ] || fail "$output"
for _ in $(seq $TRIES); do
	[ "$(reported "stopped receive")" = 1 ] && break
	sleep 0.1
done
lunatik stop "$HOLDER" > /dev/null 2>&1

refused receive "coroutine receive" request registration channel bind "protocol option" "packet close" stop "percpu stop" \
	"helper body receive" "helper body request" "helper resume receive" "helper resume request" "stopped receive"
accepted "socket option" send close nest
ktap_pass "a thread body of a runtime with a netdevice notifier, and a runtime it creates and resumes, are refused the same"

accepted "close stop" "close percpu stop" "close helper stop"
ktap_pass "the finalizers of the spawned runtime's close stop the runtimes"

check_dmesg && ktap_pass "no Lua errors in kernel from the thread body"

lunatik stop "$SCRIPT"
after=$(cat /sys/module/$MODULE/refcnt 2> /dev/null)
[ "$after" = "$before" ] || fail "$MODULE use count went from $before to $after"
ktap_pass "the module's use count is left as it was"

ktap_totals

