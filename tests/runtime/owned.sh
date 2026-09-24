#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A registered object is the runtime's until its close: not the registry's,
# and not its finalizer's.
#
# owned.lua creates lunatik_owned, drops its handle, clears every registry slot
# that still names it, as debug.getregistry() lets a script do, and collects:
# the device is still in /dev when the script returns, since the runtime holds
# the object on a list the script cannot reach, and it goes at the runtime's
# stop. owned_unfinalized.lua creates lunatik_unfinalized and clears __gc off
# the class metatable, and lunatik_swapped and swaps its metatable for an empty
# one with debug.setmetatable, so the collector runs no finalizer on either:
# both go at the runtime's stop all the same, since the close releases what the
# runtime owns before the collector runs and puts it after. A build that leaves
# them to the finalizer keeps the devices past the stop, with their file
# operations in a module lunatik reload then unloads, so that half skips unless
# the loaded core lists lunatik_closeobjects in /proc/kallsyms.
#
# Usage: sudo bash tests/runtime/owned.sh

SCRIPT="tests/runtime/owned"
UNFINALIZED="tests/runtime/owned_unfinalized"
OWNED="lunatik_owned"
DEVICES="lunatik_unfinalized lunatik_swapped"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$UNFINALIZED" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"
[ -c "/dev/$OWNED" ] || fail "the device went with the registry slots that named its handle"
lunatik stop "$SCRIPT" > /dev/null 2>&1
[ ! -e "/dev/$OWNED" ] || fail "the device outlived its runtime"
ktap_pass "a registered object whose handle and registry slots are gone lives until its runtime stops"

if grep -Eq " lunatik_closeobjects[[:space:]]\[lunatik\]$" /proc/kallsyms 2>/dev/null; then
	run_script "$UNFINALIZED"
	for device in $DEVICES; do
		[ -c "/dev/$device" ] || fail "$device did not appear"
	done
	lunatik stop "$UNFINALIZED" > /dev/null 2>&1
	for device in $DEVICES; do
		[ ! -e "/dev/$device" ] || fail "$device outlived its runtime with no finalizer to release it"
	done
	ktap_pass "a registered object goes with its runtime when a script cleared its __gc or swapped its metatable"
else
	ktap_skip "no lunatik_closeobjects in the loaded core: a device with no finalizer would outlive its module"
fi

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

