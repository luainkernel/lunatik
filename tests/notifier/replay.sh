#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# notifier.netdevice tells the callback which events the registration replays:
# register_netdevice_notifier_net delivers a REGISTER, and an UP for a device
# that is up, for every device the namespace already has, inside the
# registration call and under the same name and code a live event carries. A
# script that means what appears after it registered, as ifquarantine does,
# cannot tell the two apart by itself, so the callback's last argument,
# `replayed`, is true for a replayed event and false for a live one.
#
# The replay is delivered inside register_netdevice_notifier_net and a live
# event under RTNL before the ip command that caused it returns, so each
# assertion reads what the callback already printed. A dummy device brought up
# before the script runs is replayed as a REGISTER and an UP, both marked; one
# created, brought up and deleted afterwards is reported live, none marked; and
# the count of marked events does not grow once the registration has returned.
#
# Usage: sudo bash tests/notifier/replay.sh

SCRIPT="tests/notifier/replay"
OLDDEV="replay0"
NEWDEV="replay1"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ip link del "$OLDDEV" 2> /dev/null
	ip link del "$NEWDEV" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 7

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "replay marks the REGISTER of a device that already exists"
	ktap_skip "replay marks the UP of a device that is already up"
	ktap_skip "live register is not marked"
	ktap_skip "live up is not marked"
	ktap_skip "live unregister is not marked"
	ktap_skip "no event is marked once the registration has returned"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "replay: $1"
}

marked()
{
	dmesg_since | grep -cE "^.*replay: .* true$"
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
ip link add "$OLDDEV" type dummy 2> /dev/null || skip_all "cannot create a dummy device"
ip link set "$OLDDEV" up || fail "cannot bring $OLDDEV up"

mark_dmesg
run_script "$SCRIPT"

[ "$(reported "register $OLDDEV true")" = 1 ] || fail "the REGISTER of $OLDDEV was not marked as replayed"
ktap_pass "replay marks the REGISTER of a device that already exists"

[ "$(reported "up $OLDDEV true")" = 1 ] || fail "the UP of $OLDDEV was not marked as replayed"
ktap_pass "replay marks the UP of a device that is already up"

replayed=$(marked)

ip link add "$NEWDEV" type dummy || fail "cannot create $NEWDEV"
[ "$(reported "register $NEWDEV false")" = 1 ] || fail "the live REGISTER of $NEWDEV was not reported unmarked"
ktap_pass "live register is not marked"

ip link set "$NEWDEV" up || fail "cannot bring $NEWDEV up"
[ "$(reported "up $NEWDEV false")" = 1 ] || fail "the live UP of $NEWDEV was not reported unmarked"
ktap_pass "live up is not marked"

ip link del "$NEWDEV" || fail "cannot delete $NEWDEV"
[ "$(reported "unregister $NEWDEV false")" = 1 ] || fail "the live UNREGISTER of $NEWDEV was not reported unmarked"
ktap_pass "live unregister is not marked"

[ "$(marked)" = "$replayed" ] || fail "$(( $(marked) - replayed )) events were marked after the registration returned"
ktap_pass "no event is marked once the registration has returned"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

