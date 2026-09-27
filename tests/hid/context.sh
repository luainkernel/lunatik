#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# hid.register from a callback is refused, and accepted from the script body.
#
# A probe, report_fixup or raw_event callback runs under the softirq runtime's
# spinlock, and registering a driver allocates with GFP_KERNEL, adds a kobject
# and takes the device lock of each device on the bus, any of which sleeps.
# context.lua creates a softirq runtime whose body, which runs in process
# context, registers a driver, and resumes it past the body, the armed state a
# callback runs in, where registering another is refused with the message the
# case asserts. A build without the refusal registers that driver under the
# spinlock, so the case skips unless the loaded luahid is the installed one and
# that file carries the refusal, which is inline and has no symbol of its own.
#
# Usage: sudo bash tests/hid/context.sh

SCRIPT="tests/hid/context"
MODULE="luahid"
REFUSAL="not allowed after module load"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if ! [ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] ||
	! grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"; then
	ktap_skip "hid/context: the loaded $MODULE does not carry the refusal: it would register under a spinlock"
elif run_test "$SCRIPT"; then
	ktap_pass "hid/context"
else
	ktap_fail "hid/context"
fi

ktap_totals

