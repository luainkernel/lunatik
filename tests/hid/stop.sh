#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A hid driver's stop unregisters it while the script body loads, its __close is
# that stop, and the stop is refused once the runtime is armed.
#
# stop.lua runs stop_drivers in a softirq runtime through the runner, which
# keeps it under its name. That body registers three drivers under a vendor no
# device on the bus carries: one it stops twice, one held by a to-be-closed
# variable that goes out of scope, whose metatable holds one function under
# __close and stop, and one it keeps. stop.lua then resumes the runtime past its
# body, the armed state a callback runs in, where stopping the kept driver is
# refused with the message the case asserts, since hid_unregister_driver sleeps.
# /sys/bus/hid/drivers then holds the kept driver and neither of the others, and
# the kept one leaves the bus with its runtime, with no error or warning in the
# kernel log.
#
# Usage: sudo bash tests/hid/stop.sh

SCRIPT="tests/hid/stop"
DRIVERS="tests/hid/stop_drivers"
BUS=/sys/bus/hid/drivers

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$DRIVERS" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

[ -d /sys/bus/hid ] || skip "hid/stop: the kernel has no HID bus"

ktap_header
ktap_plan 6

if run_test "$SCRIPT"; then
	ktap_pass "hid/stop: stop is refused once the runtime is armed"
else
	ktap_fail "hid/stop: stop is refused once the runtime is armed"
fi

[ -d "$BUS/lunatik_hid_stopped" ] && fail "a driver stopped twice is still on the hid bus"
ktap_pass "a driver stopped twice leaves the hid bus"

[ -d "$BUS/lunatik_hid_closed" ] && fail "a to-be-closed driver is still on the hid bus after its scope"
ktap_pass "a to-be-closed variable stops a driver, through the stop it holds as __close"

[ -d "$BUS/lunatik_hid_kept" ] || fail "the driver whose stop was refused is not on the hid bus"
ktap_pass "the driver whose stop was refused stays on the hid bus"

lunatik stop "$DRIVERS" > /dev/null 2>&1
[ -d "$BUS/lunatik_hid_kept" ] && fail "the kept driver outlived its runtime"
ktap_pass "the kept driver leaves the hid bus with its runtime"

check_dmesg && ktap_pass "hid/stop: no Lua errors, kernel warnings or oopses"

ktap_totals

