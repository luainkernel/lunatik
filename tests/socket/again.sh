#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what socket:receive() and socket:accept() answer when their wait ends with
# nothing, which the kernel reports as EAGAIN: nil and "EAGAIN", alone, both for a
# nonblocking call (MSG_DONTWAIT, O_NONBLOCK) and for one a receive timeout bounds,
# and through inet.udp:receivefrom(), which converts the sender's address only when
# there is one. A wait that finds a message or a connection answers it, and a
# failure other than EAGAIN still raises its errno's name: ENOTCONN for a receive on
# a listener and EINVAL for an accept on a socket that does not listen.
#
# Usage: sudo bash tests/socket/again.sh

SCRIPT="tests/socket/again"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

if run_test "$SCRIPT"; then
	ktap_pass "socket again: receive and accept answer nil and EAGAIN for a wait that ends with nothing"
else
	ktap_fail "socket again: receive and accept answer nil and EAGAIN for a wait that ends with nothing"
fi

ktap_totals

