#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests skb:resize on non-linear and linear skbs.
#
# A LOCAL_OUT netfilter hook resizes the first data segment of five TCP
# connections over loopback. tcp_sendmsg copies a segment's payload into page
# fragments and keeps only the headers in the linear head, so every such segment
# is non-linear. Each sender sets its own SO_PRIORITY, which picks the case: a
# shrink inside the payload, a shrink below the linear head, a grow, a grow past
# any tailroom, which answers false, a negative length, which raises "out of
# bounds", and a shrink to the IPv4 header alone, which answers false too: a TCP
# segment leaves the socket CHECKSUM_PARTIAL, its checksum field for the device
# or skb_checksum_help to fill, and pskb_trim_rcsum refuses to cut it, where a
# trim past it reaches skb_checksum_help's WARN on a device without checksum
# offload (net/core/dev.c at 6.8). What does not fit leaves #skb as it was, and
# a resize that does answers true. A UDP datagram of the same size is linear, since
# ip_append_data keeps a datagram under SKB_MAX_ALLOC in the head, and takes a
# shrink; a second one is shrunk and grown back over its own payload, which is
# never zero, so a grow that leaves those bytes in place fails whether or not the
# kernel zeroes its allocations (init_on_alloc). Each case that resizes reads back
# #skb and #skb:data() at the requested length, a grow reads the bytes it added as
# zeros, and dmesg carries no WARNING. The payload is larger than the head's free
# space, so linearizing reallocates the head with 128 spare bytes
# (__pskb_pull_tail), which the grow stays under. The hook drops the packet it
# resized; TCP resends it untouched, and the UDP send fails with EPERM, so the
# senders' errors are discarded.
#
# The priorities are outside 0..6, which only a process with CAP_NET_ADMIN or
# CAP_NET_RAW may set, so no other process on the host picks a case.
#
# Usage: sudo bash tests/skb/resize.sh

SCRIPT="tests/skb/resize"
PORT=5564
PAYLOAD=2048          # PAYLOAD in resize.lua
PRIORITY=$((0x12360000)) # PRIORITY in resize.lua
CASES="shrink head grow overgrow linear negative regrow checksum"
NCASES=$(echo $CASES | wc -w)

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

LISTENER=""

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	[ -n "$LISTENER" ] && kill "$LISTENER" 2>/dev/null
	pkill -f "TCP-LISTEN:$PORT," 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $((NCASES + 1))

if ! command -v socat > /dev/null 2>&1; then
	for c in $CASES; do ktap_skip "resize $c — socat unavailable"; done
	ktap_skip "no Lua errors, kernel warnings or oopses — socat unavailable"
	ktap_totals
	exit 0
fi

mark_dmesg
run_script --context=softirq "$SCRIPT"

socat -u "TCP-LISTEN:$PORT,reuseaddr,fork" OPEN:/dev/null &
LISTENER=$!
for _ in $(seq 20); do [ -n "$(ss -tHln "sport = :$PORT" 2>/dev/null)" ] && break; sleep 0.1; done

i=1
for c in $CASES; do
	proto=TCP
	case $c in linear|regrow) proto=UDP ;; esac
	head -c "$PAYLOAD" /dev/zero | tr '\0' x | timeout 5 socat -u - "$proto:127.0.0.1:$PORT,priority=$((PRIORITY + i))" 2>/dev/null
	i=$((i + 1))
done

for _ in $(seq 20); do
	[ "$(dmesg_since | grep -c "skb resize: ")" -ge "$NCASES" ] && break
	sleep 0.5
done

lunatik stop "$SCRIPT"
out=$(dmesg_since)

for c in $CASES; do
	if echo "$out" | grep -q "skb resize: $c ok"; then
		ktap_pass "resize $c"
	else
		ktap_fail "resize $c"
		comment "$(echo "$out" | grep "skb resize: $c" || echo "no hook output")"
	fi
done

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

