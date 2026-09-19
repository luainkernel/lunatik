#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that the harness sees a spawned body die, and only then. A thread body
# raising a bare errno re-raises at level 0, so the message carries no position
# and the Lua pattern in KTAP_ERRORS cannot match it; what names the death is
# luathread's own log, at error level. It spells its three benign stops the
# same way at warning level, and a check that read the text alone turned the
# one tests/thread/name.sh races into an intermittent failure of that suite.
#
# The second case writes that benign line itself: it comes of a thread stopped
# before it was ever scheduled, which no script can ask for on demand.
#
# Usage: sudo bash tests/thread/died.sh

SCRIPT="tests/thread/died"
BENIGN="<4>luathread: [0000000000000000] thread has never run"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg

output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
sleep 1

dmesg --level=err 2>/dev/null | grep -qE "$KTAP_ERRORS_ERR" ||
	fail "a body that died left no error the harness matches"
mark_dmesg
ktap_pass "a thread body that dies of a bare errno is an error the harness sees"

echo "$BENIGN" > /dev/kmsg
check_dmesg || { ktap_totals; exit 1; }
mark_dmesg
ktap_pass "a stop luathread reports at warning level is not one"

ktap_totals

