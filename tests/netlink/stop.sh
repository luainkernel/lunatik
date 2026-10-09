#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A channel's stop unregisters its family while the script body loads, its
# __close is that stop, and the stop is refused once an interrupt-context
# runtime is armed and accepted once a process runtime is.
#
# The body of stop_channels creates three channels: one it stops twice, whose
# multicast and unicast then raise, which it reports, one held by a to-be-closed
# variable that goes out of scope, whose metatable holds one function under
# __close and stop, and one it keeps. stop.lua runs it in a process runtime,
# then in a softirq one through the runner, which keeps it under its name, and
# resumes each past its body, the armed state a callback runs in. Stopping the
# kept channel there is accepted in the process runtime and refused in the
# softirq one with the message the case asserts, since genl_unregister_family
# sleeps; the process runtime is closed after its case. genl ctrl then resolves
# the softirq runtime's kept family and not the process runtime's, and the kept
# one leaves with its runtime, with no error or warning in the kernel log.
#
# Usage: sudo bash tests/netlink/stop.sh

SCRIPT="tests/netlink/stop"
CHANNELS="tests/netlink/stop_channels"
MODULE="luanetlink"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$CHANNELS" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip "netlink/stop: $MODULE not loaded"
command -v genl > /dev/null 2>&1 || skip "netlink/stop: genl tool unavailable"

registered() { genl ctrl get name "$1" > /dev/null 2>&1; }

ktap_header
ktap_plan 7

if run_test "$SCRIPT"; then
	ktap_pass "netlink/stop: stop is accepted past a process runtime's body and refused past an IRQ one's"
else
	ktap_fail "netlink/stop: stop is accepted past a process runtime's body and refused past an IRQ one's"
fi

registered lunatik_kept || fail "the channel whose stop was refused has no family"
ktap_pass "the channel whose stop was refused keeps its family"

registered lunatik_stopped && fail "a channel stopped twice still has its family"
ktap_pass "a channel stopped twice unregisters its family"

registered lunatik_closed && fail "a to-be-closed channel still has its family after its scope"
ktap_pass "a to-be-closed variable stops a channel, through the stop it holds as __close"

dmesg_since | grep -qF "netlink stop test: a stopped channel raises" || fail "a stopped channel's multicast or unicast did not raise"
ktap_pass "a stopped channel's multicast and unicast raise"

lunatik stop "$CHANNELS" > /dev/null 2>&1
registered lunatik_kept && fail "the kept channel's family outlived its runtime"
ktap_pass "the kept channel's family goes with its runtime"

check_dmesg && ktap_pass "netlink/stop: no Lua errors, kernel warnings or oopses"

ktap_totals

