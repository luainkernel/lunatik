#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that socket.tls.connect composes the three calls it is: socket.new,
# connect, and the client hello. On a host with no agent the hello is where it
# stops, so ESRCH is the reading that the two calls before it ran and the
# socket reached the upcall connected and carrying a file; anything the module
# spells wrong raises a Lua error instead, and never reaches an errno at all.
#
# A completed handshake is what would prove the keyed socket it hands back, and
# that needs tlshd. Skipped whole where one is installed or running, for the
# same reason upcall.sh is.
#
# Usage: sudo bash tests/handshake/socket_tls.sh

SCRIPT="tests/handshake/socket_tls"
MODULE="luahandshake"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "socket_tls: connect reaches the upcall"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
command -v tlshd > /dev/null 2>&1 && skip_all "tlshd is installed, so an agent may answer"
pgrep -x tlshd > /dev/null 2>&1 && skip_all "a tlshd process is running"

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "socket.tls connect: the socket is connected and the hello reaches submit" ||
	fail "socket.tls.connect did not reach the upcall"
ktap_pass "socket_tls: connect reaches the upcall"

ktap_totals

