#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the address getsockname(), getpeername() and receivefrom() answer with,
# for the families a single script can exercise. The kernel reports how many bytes it
# filled, and the assertion is that the answer is those bytes and no more: an AF_INET6
# socket names 26, unpacked field by field. An AF_PACKET address is five values, the
# protocol in host order, the interface, the packet type, the hardware type and the
# hardware address, compared one by one on an unbound socket, on one bound to
# loopback and on a received frame, and its getpeername is refused, as packet_getname
# names no peer. A receivefrom where the protocol names no sender, TCP among them,
# must answer with the message alone, as receive does whatever the protocol names,
# and socket.inet's udp receivefrom answers with the sender's address as a string.
#
# Every case that counts bytes or values discriminates: an address pushed as the whole
# storage is 126 bytes whatever the family wrote, and a receive that reads a family
# nobody set answers with a second value built from the stack. The AF_PACKET cases
# also read the protocol back through both conversions, the unbound one as socket.new
# took it and the bound one as bind did, and the received frame's hardware address as
# the 6 bytes its length names rather than the 8 of the name packet_recvmsg widens.
# The AF_INET and AF_NETLINK cases do not; they guard the arms this leaves alone.
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
ktap_plan 14

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
expect "inet receivefrom ok" "socket receivefrom: a datagram names the sender's address and port"
expect "inet receive answers with the message alone" "socket receive: a datagram answers with the message alone"
expect "inet.udp receivefrom names the sender as a string" "socket.inet: a udp receivefrom names the sender's address as a string and its port"
expect "inet receivefrom names no sender" "socket receivefrom: a connected TCP socket answers with the message alone"
expect "netlink getsockname ok" "socket getsockname: an AF_NETLINK socket answers with its pid and group mask"
expect "netlink receivefrom ok" "socket receivefrom: a netlink datagram names the sending pid and group mask"
expect "inet6 getsockname ok" "socket getsockname: an AF_INET6 socket answers with the 26 bytes past the family" inet6
expect "packet getsockname unbound ok" "socket getsockname: an unbound AF_PACKET socket answers with the protocol socket.new took" packet
expect "packet getpeername refused" "socket getpeername: an AF_PACKET socket names no peer and is refused with EOPNOTSUPP" packet
expect "packet getsockname bound ok" "socket getsockname: a bound AF_PACKET socket answers with the interface and its hardware address" packet
expect "packet receivefrom ok" "socket receivefrom: a frame names its protocol, interface, packet type and sender" packet

cleanup
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

