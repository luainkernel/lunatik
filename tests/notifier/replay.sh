#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A netdevice callback receives, as its fourth argument, whether the event is
# one the registration replays: register_netdevice_notifier delivers a
# REGISTER, and an UP for a device that is up, for every device the namespace
# already has, under the same name and code a live event carries, and
# notifier.netdevice marks each as it queues it, by the task that registered.
#
# Each event reaches the callback on a kernel worker after the ip command that
# caused it returns, so each assertion waits for the line it reads. A dummy
# device brought up before the script runs is replayed as a REGISTER and an
# UP, both marked; one created, brought up and deleted afterwards is reported
# live, unmarked, and in the order its events came; and the count of marked
# events does not grow once the replay has reached the callback, which the live
# REGISTER that follows it in the queue tells.
# The fifth argument is the device's index: the live REGISTER of a new dummy
# carries the index sysfs gives it, and so does the REGISTER of a dummy renamed
# right after its creation, which reaches the callback after the rename under
# the name the event carried.
#
# Usage: sudo bash tests/notifier/replay.sh

SCRIPT="tests/notifier/replay"
OLDDEV="replay0"
NEWDEV="replay1"
RENDEV="replay2"
RENAMED="replay3"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ip link del "$OLDDEV" 2> /dev/null
	ip link del "$NEWDEV" 2> /dev/null
	ip link del "$RENDEV" 2> /dev/null
	ip link del "$RENAMED" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 10

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "replay marks the REGISTER of a device that already exists"
	ktap_skip "replay marks the UP of a device that is already up"
	ktap_skip "live register is not marked"
	ktap_skip "live up is not marked"
	ktap_skip "live unregister is not marked"
	ktap_skip "the live events reach the callback in the order they came"
	ktap_skip "no event is marked once the registration has returned"
	ktap_skip "the callback receives the index of the device it reports"
	ktap_skip "a device renamed before its REGISTER reaches the callback keeps its index"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "replay: $1"
}

reports()
{
	[ "$(reported "$1")" = 1 ]
}

reports_index()
{
	dmesg_since | grep -qxE ".*index: $1"
}

marked()
{
	dmesg_since | grep -cE "replay: .* true$"
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
ip link add "$OLDDEV" type dummy 2> /dev/null || skip_all "cannot create a dummy device"
ip link set "$OLDDEV" up || fail "cannot bring $OLDDEV up"

mark_dmesg
run_script "$SCRIPT"

awaited reports "register $OLDDEV true" || fail "the REGISTER of $OLDDEV was not marked as replayed"
ktap_pass "replay marks the REGISTER of a device that already exists"

awaited reports "up $OLDDEV true" || fail "the UP of $OLDDEV was not marked as replayed"
ktap_pass "replay marks the UP of a device that is already up"

ip link add "$NEWDEV" type dummy || fail "cannot create $NEWDEV"
awaited reports "register $NEWDEV false" || fail "the live REGISTER of $NEWDEV was not reported unmarked"
ktap_pass "live register is not marked"

index=$(cat "/sys/class/net/$NEWDEV/ifindex")
awaited reports_index "register $NEWDEV $index" || fail "the REGISTER of $NEWDEV did not carry its index $index"
ktap_pass "the callback receives the index of the device it reports"
replayed=$(marked) # every replay was queued before this REGISTER, and the callback takes them in order

ip link set "$NEWDEV" up || fail "cannot bring $NEWDEV up"
awaited reports "up $NEWDEV false" || fail "the live UP of $NEWDEV was not reported unmarked"
ktap_pass "live up is not marked"

ip link del "$NEWDEV" || fail "cannot delete $NEWDEV"
awaited reports "unregister $NEWDEV false" || fail "the live UNREGISTER of $NEWDEV was not reported unmarked"
ktap_pass "live unregister is not marked"

order=$(dmesg_since | grep -oE "replay: [a-z]+ $NEWDEV" | cut -d' ' -f2 | paste -sd' ')
[ "$order" = "register up unregister" ] || fail "the events of $NEWDEV reached the callback as: $order"
ktap_pass "the live events reach the callback in the order they came"

[ "$(marked)" = "$replayed" ] || fail "$(( $(marked) - replayed )) events were marked after the registration returned"
ktap_pass "no event is marked once the registration has returned"

ip link add "$RENDEV" type dummy && ip link set "$RENDEV" name "$RENAMED" || fail "cannot create and rename $RENDEV"
index=$(cat "/sys/class/net/$RENAMED/ifindex")
awaited reports_index "register $RENDEV $index" || fail "the REGISTER of $RENDEV, renamed $RENAMED, did not carry its index $index"
ktap_pass "a device renamed before its REGISTER reaches the callback keeps its index"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

