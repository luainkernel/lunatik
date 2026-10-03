#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A netdevice event waits on no runtime's lock under RTNL: a thread body of the
# runtime that registered the notifier holds that runtime's lock for as long as
# it runs, and takes RTNL itself while an event is pending there.
#
# lock.sh spawns lock.lua: its script body registers a netdevice notifier, and
# its thread body, which holds the runtime's lock from start to end, waits for
# lock0 to exist and brings it up through netlink.rt, a request rtnetlink serves
# under RTNL. The test creates lock0 while the body waits. The REGISTER is
# raised under RTNL on the ip command's task, where a callback dispatched in
# place would wait on the body's lock with RTNL held while the body's request
# waits on RTNL. Queued instead, the ip command returns, the request is
# answered, and the REGISTER and the UP the request raised reach the callback
# after the body returns, in that order.
#
# A build that runs the callback under RTNL wedges RTNL rather than failing, so
# the test runs only on a build that defers the callback, and skips unless the
# loaded luanotifier lists luanotifier_drain in /proc/kallsyms. The body ends on
# its own once it has brought lock0 up, or after its last look for it.
#
# Usage: sudo bash tests/notifier/lock.sh

SCRIPT="tests/notifier/lock"
MODULE="luanotifier"
DRAIN="luanotifier_drain"
DEVICE="lock0"
WAIT=10 # seconds the ip command is given to return

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ip link del "$DEVICE" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "a device is created while a thread body holds the lock of the runtime with the notifier"
	ktap_skip "the body's request, which takes RTNL, is answered while the event waits on its lock"
	ktap_skip "the events reach the callback once the body returns, in the order they came"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

lines()
{
	dmesg_since | grep -oE "notifier lock test: (set up|register|up|no device)$" | sed 's/^notifier lock test: //'
}

delivered()
{
	lines | grep -qx up
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
command -v timeout > /dev/null 2>&1 || skip_all "timeout not available"
grep -Eq " $DRAIN[[:space:]]\[$MODULE\]$" /proc/kallsyms 2> /dev/null ||
	skip_all "no $DRAIN in the loaded $MODULE: it runs the callback under RTNL"

mark_dmesg
spawned=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$spawned" ] || fail "spawning $SCRIPT: $spawned"

timeout "$WAIT" ip link add "$DEVICE" type dummy || fail "ip link add $DEVICE did not return within ${WAIT}s"
ktap_pass "a device is created while a thread body holds the lock of the runtime with the notifier"

awaited delivered || fail "the events of $DEVICE did not reach the callback: $(lines | paste -sd' ')"
[ "$(lines | head -1)" = "set up" ] || fail "the body did not bring $DEVICE up: $(lines | paste -sd' ')"
ktap_pass "the body's request, which takes RTNL, is answered while the event waits on its lock"

order=$(lines | awk '!seen[$0]++' | paste -sd' ') # a host that toggles lock0 again adds no first
[ "$order" = "set up register up" ] || fail "the body and the callback reported: $order"
ktap_pass "the events reach the callback once the body returns, in the order they came"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

