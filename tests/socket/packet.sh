#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the AF_PACKET address a socket:send() with a destination builds. The script
# names the protocol and the interface; the kernel reads the rest of the same
# struct sockaddr_ll, sll_halen bounding the send and sll_addr becoming the frame's
# destination hardware address. A SOCK_DGRAM send on loopback is read back on a
# SOCK_RAW socket bound to the same ethertype, and its destination must be the
# zeros the binding declares rather than whatever the storage held.
#
# What discriminates is the send itself: an undeclared sll_halen is stack, and
# packet_snd refuses whatever exceeds 8. The destination is the contract rather
# than a second discriminator, since stack can hold zeros.
#
# The next two cases pin the protocol socket.new takes in host order and hands
# packet_create as the __be16 it reads: an unbound socket created with the
# ethertype receives the frame, one created with it already in network order is
# registered for the swapped number and hears nothing. The pair discriminates
# because the frame carries only one ethertype. A protocol past 16 bits is
# refused rather than cut to the low half packet_create's cast would keep.
#
# The last two cases pin the refusal of SOCK_PACKET, whose address is a struct
# sockaddr_pkt no method spells, on AF_PACKET and on AF_INET, which __sock_create
# turns into AF_PACKET: the kernel creates the socket in both, and a refusal keyed
# on the family would pass the first case and fail the second.
#
# Usage: sudo bash tests/socket/packet.sh

SCRIPT="tests/socket/packet"
PAYLOAD="lunatikpacket"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 7

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

[ -e /proc/net/packet ] || {
	echo "# SKIP: no AF_PACKET support"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "socket packet: frame carries $PAYLOAD" || fail "the frame did not carry the payload"
ktap_pass "packet: a DGRAM send names the protocol and the interface of the frame"

dmesg_since | grep -q "socket packet: destination 00:00:00:00:00:00" || fail "unexpected destination: $(dmesg_since | grep 'socket packet: destination')"
ktap_pass "packet: the destination hardware address is the one the binding declares"

dmesg_since | grep -q "socket packet: host order reaches the unbound socket" || fail "the host order socket did not receive the frame"
ktap_pass "packet: a socket created with the ethertype in host order receives it"

dmesg_since | grep -q "socket packet: network order misses it" || fail "the network order socket received a frame it is not registered for"
ktap_pass "packet: a socket created with the ethertype in network order does not"

dmesg_since | grep -q "socket packet: a protocol past 16 bits raises .*out of bounds" || fail "unexpected answer: $(dmesg_since | grep 'socket packet: a protocol past')"
ktap_pass "packet: socket.new refuses an AF_PACKET protocol past 16 bits"

dmesg_since | grep -q "socket packet: SOCK_PACKET on AF_PACKET raises .*unsupported socket type" || fail "unexpected answer: $(dmesg_since | grep 'socket packet: SOCK_PACKET on AF_PACKET')"
ktap_pass "packet: socket.new refuses SOCK_PACKET on AF_PACKET"

dmesg_since | grep -q "socket packet: SOCK_PACKET on AF_INET raises .*unsupported socket type" || fail "unexpected answer: $(dmesg_since | grep 'socket packet: SOCK_PACKET on AF_INET')"
ktap_pass "packet: socket.new refuses SOCK_PACKET on AF_INET, which the kernel makes an AF_PACKET socket"

ktap_totals

