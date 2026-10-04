#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A netdevice callback's return reaches the chain only when it is a
# linux.notify code: any other value counts as notify.DONE and is logged as
# "invalid notify code". code.lua answers the REGISTER of five dummy devices:
# 5000 for the first, which notifier_to_errno turns into an errno past
# MAX_ERRNO when the chain ends on it, which register_netdevice returns and an
# ERR_PTR caller takes for a pointer; notify.BAD spelled as a string for the
# second, which lua_tointeger reads as the code; one past notify.BAD and -1 for
# the third and fourth, just outside the codes on either side; and notify.BAD
# for the fifth. The first four register and log the refusal, and the fifth is
# vetoed, as a code still is. A build without the refusal logs none of them,
# which the first case reads.
#
# Usage: sudo bash tests/notifier/code.sh

SCRIPT="tests/notifier/code"
WIDE="codewide0"
STRING="codestr0"
PAST="codepast0"
NEGATIVE="codeneg0"
BAD="codebad0"
INVALID="luanotifier: invalid notify code"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	for dev in "$WIDE" "$STRING" "$PAST" "$NEGATIVE" "$BAD"; do ip link del "$dev" 2> /dev/null; done
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

mark_dmesg
run_script --context=softirq "$SCRIPT"

# refused <dev> <description>: the device registers and the refusal is logged once
refused()
{
	ip link add "$1" type dummy 2> /dev/null || fail "$2: the registration was vetoed"
	[ "$(dmesg_since | grep -cF "$INVALID")" -ge "$3" ] || fail "$2: the refusal was not logged"
	ktap_pass "$2"
}

refused "$WIDE" "a number past the notify codes counts as DONE and is logged" 1
refused "$STRING" "a notify code spelled as a string counts as DONE and is logged" 2
refused "$PAST" "one past notify.BAD counts as DONE and is logged" 3
refused "$NEGATIVE" "a negative number counts as DONE and is logged" 4

ip link add "$BAD" type dummy 2> /dev/null && fail "notify.BAD did not veto the registration"
ktap_pass "notify.BAD still vetoes the registration"

lunatik stop "$SCRIPT"
check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

