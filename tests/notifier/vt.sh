#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# notifier.vt, registered from a hardirq runtime, hands its callback the event,
# the character and the console of a write to a virtual terminal: a character
# written to /dev/tty1, console 0, reaches it as a linux.vt.event PREWRITE before
# con_write draws it and as a WRITE once drawn, and the UPDATE that ends the
# write carries no character, all inside the write. Opening /dev/tty63, console
# 62, allocates it and deallocvt deallocates it, each inside the call, and the
# ALLOCATE and DEALLOCATE carry no character either: vc_allocate and
# vc_deallocate leave it uninitialized, 0 on a kernel that zeroes its stack, so
# each case asserts nil rather than a value. Each assertion reads what the
# callback already printed. The script reports each event once, on its
# console, and a write only for a character the host has no reason to write
# there. Skips without a /dev/tty1, which only CONFIG_VT registers, and the
# allocation cases without deallocvt or with /dev/tty63 held by the host.
#
# Usage: sudo bash tests/notifier/vt.sh

SCRIPT="tests/notifier/vt"
TTY="/dev/tty1"
MARK='`' # must match MARK in vt.lua
CHAR=$(printf '%d' "'$MARK") # MARK as the script reports it
SPARE=63 # /dev/tty63, console 62, SPARE in vt.lua
TRIES=50 # the close of a console puts its port from a work item, and a console still held is busy

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	deallocvt "$SPARE" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "a write reaches the callback as a PREWRITE of its character on its console"
	ktap_skip "a write reaches the callback as a WRITE of its character on its console"
	ktap_skip "the UPDATE that ends a write carries no character"
	ktap_skip "an allocation reaches the callback as an ALLOCATE with no character"
	ktap_skip "a deallocation reaches the callback as a DEALLOCATE with no character"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

[ -c "$TTY" ] || skip_all "no $TTY"

skip=""
command -v deallocvt > /dev/null || skip="no deallocvt"
[ -c "/dev/tty$SPARE" ] || skip="no /dev/tty$SPARE"
[ -e "/sys/class/vc/vcs$SPARE" ] && skip="/dev/tty$SPARE is held by the host"

deallocate()
{
	for _ in $(seq "$TRIES"); do
		deallocvt "$SPARE" 2> /dev/null && return 0
		sleep 0.1
	done
	return 1
}

carried() { dmesg_since | sed -n "s/.*notifier vt: $1 //p"; }

mark_dmesg
run_script --context=hardirq "$SCRIPT"
printf '%s' "$MARK" > "$TTY" || fail "cannot write to $TTY"
if [ -z "$skip" ]; then
	: < "/dev/tty$SPARE" || fail "cannot open /dev/tty$SPARE"
	deallocate || fail "cannot deallocate /dev/tty$SPARE"
fi
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$(carried prewrite)" = "$CHAR" ] || fail "the write to $TTY was not reported as a PREWRITE"
ktap_pass "a write reaches the callback as a PREWRITE of its character on its console"

[ "$(carried write)" = "$CHAR" ] || fail "the write to $TTY was not reported as a WRITE"
ktap_pass "a write reaches the callback as a WRITE of its character on its console"

[ "$(carried update)" = nil ] || fail "the UPDATE of $TTY carried '$(carried update)'"
ktap_pass "the UPDATE that ends a write carries no character"

if [ -n "$skip" ]; then
	echo "# SKIP: $skip"
	ktap_skip "an allocation reaches the callback as an ALLOCATE with no character"
	ktap_skip "a deallocation reaches the callback as a DEALLOCATE with no character"
else
	[ "$(carried allocate)" = nil ] || fail "the ALLOCATE of /dev/tty$SPARE carried '$(carried allocate)'"
	ktap_pass "an allocation reaches the callback as an ALLOCATE with no character"

	[ "$(carried deallocate)" = nil ] || fail "the DEALLOCATE of /dev/tty$SPARE carried '$(carried deallocate)'"
	ktap_pass "a deallocation reaches the callback as a DEALLOCATE with no character"
fi

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

