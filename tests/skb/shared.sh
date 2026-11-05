#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a netfilter hook's writes miss the frames a packet socket holds of the same packet.
#
# shared_tap.lua opens a packet socket for every ethertype on lo, then sends a small UDP datagram
# to a socket of its own on 127.0.0.1, with no UDP checksum and the mark of one of shared.lua's
# PRE_ROUTING hooks. The datagram is linear, and the packet socket takes a clone of it on the way out
# and another on the way in, before PRE_ROUTING, so the hook receives a head the two clones share.
# Once the datagram is delivered, which it is past the hook, the script reads the frames the packet
# socket holds. In the written case the hook flips the last byte of the packet through
# skb:data("net"): the delivered datagram carries the flip, and every frame the packet socket holds
# reads the byte as it was sent. In the summed case the hook calls skb:checksum() alone, which
# writes a UDP checksum where the datagram had none, and every frame the packet socket holds reads a
# checksum of 0. A build whose data() or checksum() writes into the head a clone shares, as one that
# linearizes and does not unshare, fails the case of that method.
#
# Usage: sudo bash tests/skb/shared.sh

SCRIPT="tests/skb/shared"
TAP="tests/skb/shared_tap"
WRITTEN="shared: a write through data() misses the frames a packet socket holds"
SUMMED="shared: checksum() misses the frames a packet socket holds"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$TAP" 2>/dev/null
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

verdict() {
	local cell="$1" title="$2"
	local failed=$(echo "$out" | grep -o "skb shared: $cell FAIL.*" | head -1)
	if [ -n "$failed" ]; then
		ktap_fail "$title: $failed"
	elif echo "$out" | grep -q "skb shared: $cell ok"; then
		ktap_pass "$title"
	else
		ktap_fail "$title: the script never reached it"
	fi
}

ktap_header
ktap_plan 2

[ -e /proc/net/packet ] || {
	echo "# SKIP: no AF_PACKET support"
	ktap_skip "$WRITTEN"
	ktap_skip "$SUMMED"
	ktap_totals
	exit 0
}

mark_dmesg
run_script --context=softirq "$SCRIPT"
run_script "$TAP"
lunatik stop "$TAP" 2>/dev/null
lunatik stop "$SCRIPT" 2>/dev/null

out=$(dmesg_since)
check_dmesg || { ktap_totals; exit 1; }
verdict written "$WRITTEN"
if echo "$out" | grep -q "skb shared: summed hooked"; then
	verdict summed "$SUMMED"
else
	ktap_fail "$SUMMED: the hook never ran"
fi
ktap_totals

