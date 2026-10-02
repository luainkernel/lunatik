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
# socket:send() answers false when a send timeout (SO_SNDTIMEO) ends its wait with
# nothing queued, which the kernel reports as EAGAIN as well: on an AF_UNIX
# datagram socket sending to a peer whose queue is full, through
# unix.dgram:sendto(), and on a TCP stream whose send and receive buffers are full,
# through inet:send(). A send that queued part of its message before the timeout
# answers that part's length, one with room answers the message's, and one with
# no destination still raises EDESTADDRREQ under a send timeout.
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
	ktap_pass "socket again: receive and accept answer nil and EAGAIN, and send answers false, for a wait that ends with nothing"
else
	ktap_fail "socket again: receive and accept answer nil and EAGAIN, and send answers false, for a wait that ends with nothing"
fi

ktap_totals

