#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the address getsockname(), getpeername() and receive(..., true) answer with,
# for the families a single script can exercise. The kernel reports how many bytes it
# filled, and the assertion is that the answer is those bytes and no more: an
# AF_PACKET socket bound to loopback names 16, an unbound one 10, a received frame 18
# and an AF_INET6 socket 26, each unpacked field by field. A protocol that names no
# sender, a TCP receive among them, must answer with the message alone.
#
# Every case that counts bytes or values discriminates: an address pushed as the whole
# storage is 126 bytes whatever the family wrote, and a receive that reads a family
# nobody set answers with a second value built from the stack. The AF_INET and
# AF_NETLINK cases do not; they guard the arms this leaves alone.
#
# Usage: sudo bash tests/socket/address.sh

SCRIPT="tests/socket/address"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

# a family the running kernel does not carry skips rather than fails
expect() { # expect <line> <description> [<family>]
	dmesg_since | grep -q "socket address: $1" && { ktap_pass "$2"; return 0; }
	[ -n "${3:-}" ] && dmesg_since | grep -q "socket address: $3 unsupported" && { ktap_skip "$2"; return 0; }
	fail "$2"
}

ktap_header
ktap_plan 11

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

expect "inet getsockname ok" "socket getsockname: an AF_INET socket answers with its address and port"
expect "inet getpeername unconnected refused" "socket getpeername: an unconnected socket is refused with ENOTCONN"
expect "inet getpeername ok" "socket getpeername: a connected socket answers with the peer's address and port"
expect "inet receivefrom ok" "socket receive: a datagram names the sender's address and port"
expect "inet receive names no sender" "socket receive: a connected TCP socket answers with the message alone"
expect "netlink getsockname ok" "socket getsockname: an AF_NETLINK socket answers with its pid and group mask"
expect "netlink receivefrom ok" "socket receive: a netlink datagram names the sending pid and group mask"
expect "inet6 getsockname ok" "socket getsockname: an AF_INET6 socket answers with the 26 bytes past the family" inet6
expect "packet getsockname unbound ok" "socket getsockname: an unbound AF_PACKET socket answers with 10 bytes" packet
expect "packet getsockname bound ok" "socket getsockname: a bound AF_PACKET socket answers with the interface's 16 bytes" packet
expect "packet receivefrom ok" "socket receive: a frame names the 18 bytes of sockaddr_ll the kernel filled" packet

cleanup
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

