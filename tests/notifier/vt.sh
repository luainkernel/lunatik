#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# notifier.vt, registered from a hardirq runtime, hands its callback the event,
# the character and the console of a write to a virtual terminal: a character
# written to /dev/tty1, console 0, reaches it as a linux.vt PREWRITE before
# con_write draws it and as a WRITE once drawn, both inside the write, so each
# assertion reads what the callback already printed. The script reports each
# event once, for that character on that console only, a character the host has
# no reason to write there. Skips without a /dev/tty1, which only CONFIG_VT
# registers.
#
# Usage: sudo bash tests/notifier/vt.sh

SCRIPT="tests/notifier/vt"
TTY="/dev/tty1"
MARK='`' # must match MARK in vt.lua

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "a write reaches the callback as a PREWRITE of its character on its console"
	ktap_skip "a write reaches the callback as a WRITE of its character on its console"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

[ -c "$TTY" ] || skip_all "no $TTY"

reported() { dmesg_since | grep -cF "notifier vt: $1"; }

mark_dmesg
run_script --context=hardirq "$SCRIPT"
printf '%s' "$MARK" > "$TTY" || fail "cannot write to $TTY"
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$(reported prewrite)" = 1 ] || fail "the write to $TTY was not reported as a PREWRITE"
ktap_pass "a write reaches the callback as a PREWRITE of its character on its console"

[ "$(reported write)" = 1 ] || fail "the write to $TTY was not reported as a WRITE"
ktap_pass "a write reaches the callback as a WRITE of its character on its console"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

