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
ktap_plan 2

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

ktap_totals

