#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An error object that is not a string reaches the caller and the kernel log
# as "error object is not a string", read without converting it.
#
# errobj.lua creates a runtime whose script raises a table as it loads, which
# lunatik.runtime refuses with that message, and a runtime of errobj_raise.lua,
# whose body raises a table, which resume refuses with it. It also creates
# lunatik_errobj, whose read raises a table: a read of the device fails with
# ECANCELED and the kernel log names the message and the operation. The same
# errobj_raise.lua, spawned, is a thread body that raises a table, and the
# kernel log names the message.
#
# Converting such an object allocates, and an allocation that fails outside a
# protected call is a BUG. What the test sees is the message: the failure needs
# the allocation to fail at that instant.
#
# Usage: sudo bash tests/runtime/errobj.sh

SCRIPT="tests/runtime/errobj"
THREAD="tests/runtime/errobj_raise"
DEVICE="lunatik_errobj"
MESSAGE="error object is not a string"
ECANCELED="Operation canceled"
TIMEOUT=5

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$THREAD" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

logged() { dmesg_since | grep -qF "$1"; }

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
ktap_pass "a script and a resume that raise a table are refused with the message"

cat "/dev/$DEVICE" 2>&1 | grep -qF "$ECANCELED" || fail "a read whose callback raises a table did not fail with ECANCELED"
logged "luadevice: $MESSAGE: read" || fail "the read's error is not in the kernel log as the message"
ktap_pass "a callback that raises a table is logged with the message"

lunatik spawn "$THREAD" > /dev/null 2>&1
for _ in $(seq $TIMEOUT); do
	logged "] $MESSAGE" && break
	sleep 1
done
logged "] $MESSAGE" || fail "a thread body that raises a table is not in the kernel log as the message"
ktap_pass "a thread body that raises a table is logged with the message"

cleanup
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

