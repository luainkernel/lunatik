#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The replay of a registration made in the script body reaches the callback
# once the body has returned.
#
# register_netdevice_notifier replays NETDEV_REGISTER (and NETDEV_UP) for each
# netdev that already exists, and notifier.netdevice queues each event for a
# kernel worker, which runs the callback under the runtime's lock. While the
# body runs the runtime is not ready, and lunatik_run answers -ENXIO there, so
# the worker waits for the body to return before it dispatches. init_dispatch.lua
# sleeps in its body after the registration, which holds the runtime not ready
# while the worker reaches it: a build that dispatches there drops the replay,
# and lo, which every namespace has, is never reported.
#
# init_dispatch_raise.lua runs that body and then raises from its own,
# which closes the runtime without arming it: the worker, waiting for the body,
# is woken by the failed load, finds the runtime closed and drops the replay,
# and its last put releases the notifier, so luanotifier's use count comes back
# and the callback never runs. A build whose worker the failed load does not
# wake keeps the notifier, and luanotifier with it, until a reboot, so this case
# runs only where the loaded luanotifier lists luanotifier_drain.
#
# Expected: the script runs without Lua error, the callback reports lo once the
# body has returned, the raising script's notifier is released without its
# callback running, and no kernel oops lands in dmesg.
#
# Usage: sudo bash tests/notifier/init_dispatch.sh

SCRIPT="tests/notifier/init_dispatch"
RAISE="tests/notifier/init_dispatch_raise"
MODULE="luanotifier"
DRAIN="luanotifier_drain"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

reported() { dmesg_since | grep -cF "init dispatch: lo"; }
replayed() { [ "$(reported)" -ge 1 ]; }
released() { [ "$(cat /sys/module/$MODULE/refcnt 2>/dev/null)" = "$before" ]; }

before=$(cat /sys/module/$MODULE/refcnt 2>/dev/null)
mark_dmesg

output=$(lunatik run "$SCRIPT" 2>&1)
[ -n "$output" ] && fail "Lua error during init-time notifier registration: $output"
ktap_pass "notifier.netdevice() at script init runs without Lua error"

awaited replayed || fail "the replay of lo did not reach the callback after the body"
ktap_pass "the replay of a registration in the script body reaches the callback after it"

lunatik stop "$SCRIPT"
if [ -z "$before" ]; then
	ktap_skip "$MODULE was not loaded before the run: no use count to come back to"
elif grep -Eq " $DRAIN[[:space:]]\[$MODULE\]$" /proc/kallsyms 2>/dev/null; then
	awaited released || fail "$MODULE use count went from $before to $(cat /sys/module/$MODULE/refcnt 2>/dev/null)"
	seen=$(reported)
	output=$(lunatik run "$RAISE" 2>&1)
	grep -qF "init dispatch: raised" <<< "$output" || fail "the raising script loaded: $output"
	awaited released || fail "$MODULE use count went from $before to $(cat /sys/module/$MODULE/refcnt 2>/dev/null)"
	[ "$(reported)" = "$seen" ] || fail "the callback ran in a runtime whose load failed"
	ktap_pass "a body that raises after registering releases its notifier, whose callback never runs"
else
	ktap_skip "no $DRAIN in the loaded $MODULE: a failed load would keep its notifier"
fi

oops=$(dmesg_since | grep -E "Oops:|BUG:|kernel BUG at|NULL pointer dereference|general protection" || true)
[ -n "$oops" ] && fail "kernel oops during init-time notifier replay: ${oops%%$'\n'*}"
ktap_pass "no kernel oops during init-time NETDEV_REGISTER replay"

ktap_totals

