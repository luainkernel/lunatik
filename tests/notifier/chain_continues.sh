#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A block whose runtime cannot take an event returned lunatik_run's -ENXIO as
# its verdict, and a negative errno has NOTIFY_STOP_MASK set, so the chain
# stopped at Lunatik's block and every notifier registered after it missed the
# event. The path exercised is the teardown: lunatik_closeprivate clears the
# runtime's private before lua_close runs the finalizers, and the block is
# unregistered by the notifier's own finalizer, so while an earlier finalizer
# holds lua_close the block is registered and the runtime is not ready. The
# body of a script past notifier.netdevice() is the other window, but reaching
# it takes a second lunatik operation while the first is in progress, which is
# not allowed.
#
# Two runtimes register in order: chain_continues_held first, whose sentinel
# finalizer sleeps at teardown, and chain_continues_after, which prints every
# REGISTER it is given. The first is stopped in the background and a dummy
# device is created inside its hold; the second must report it. The test checks
# that the stop was still running when the device was created, so a pass is
# never the hold having ended before the event.
#
# Usage: sudo bash tests/notifier/chain_continues.sh

HELD="tests/notifier/chain_continues_held"
AFTER="tests/notifier/chain_continues_after"
DEV="chaincont0"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	wait 2> /dev/null
	lunatik stop "$AFTER" > /dev/null 2>&1
	lunatik stop "$HELD" > /dev/null 2>&1
	ip link del "$DEV" 2> /dev/null
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

command -v ip > /dev/null 2>&1 || {
	echo "# SKIP: ip not available"
	ktap_skip "the device is created while the first runtime holds its teardown"
	ktap_skip "the runtime registered after sees the device"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

run_script "$HELD"
run_script "$AFTER"

mark_dmesg
lunatik stop "$HELD" > /dev/null 2>&1 &
STOP=$!
sleep 1
ip link add "$DEV" type dummy 2> /dev/null
added=$?
kill -0 "$STOP" 2> /dev/null
held=$?
wait "$STOP"

[ "$added" = 0 ] || fail "cannot create $DEV"
[ "$held" = 0 ] || fail "the hold ended before $DEV was created"
ktap_pass "the device is created while the first runtime holds its teardown"

dmesg_since | grep -qF "chain continues: register $DEV" || fail "the runtime registered after missed $DEV"
ktap_pass "the runtime registered after sees the device"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

