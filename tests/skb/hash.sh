#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that skb:hash reads skb->hash as it stands, the flow hash a socket puts on what it sends,
# and computes none where nothing set one.
#
# Three UDP flows to a local listener send two datagrams each, every flow at a priority of its own,
# which a LOCAL_OUT netfilter hook reads to tell them apart and print skb:hash. Flow 1 comes from an
# unconnected socket (socat UDP-SENDTO), whose sk_txhash connect() never set, so nothing has hashed
# its datagrams on the way out and both read 0, where a build that computes the hash, as
# skb_get_hash does, answers a nonzero one. Flows 2 and 3 come from connected sockets (socat UDP),
# whose datagrams carry the random sk_txhash connect() drew: each reads one nonzero hash on both of
# its datagrams, and the two flows read two different ones.
#
# Usage: sudo bash tests/skb/hash.sh

SCRIPT="tests/skb/hash"
PORT=5570
PRIORITY=$((0x12380000)) # PRIORITY in hash.lua
FLOWS="UDP-SENDTO UDP UDP" # flow i is sent at PRIORITY + i
DATAGRAMS=2
NFLOWS=$(echo $FLOWS | wc -w)

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	[ -n "$LISTENER" ] && kill "$LISTENER" 2>/dev/null
	pkill -f "UDP-RECV:$PORT" 2>/dev/null
}
trap cleanup EXIT
cleanup

CASES="unset flow apart"

ktap_header
ktap_plan 4

if ! command -v socat > /dev/null 2>&1; then
	for c in $CASES; do ktap_skip "hash $c — socat unavailable"; done
	ktap_skip "no Lua errors, kernel warnings or oopses — socat unavailable"
	ktap_totals
	exit 0
fi

mark_dmesg
run_script --context=softirq "$SCRIPT"

# a listener, so no port unreachable refuses a connected flow's second datagram
socat -u "UDP-RECV:$PORT,reuseaddr" OPEN:/dev/null &
LISTENER=$!
for _ in $(seq 20); do [ -n "$(ss -uHln "sport = :$PORT" 2>/dev/null)" ] && break; sleep 0.1; done

i=0
for address in $FLOWS; do
	i=$((i + 1))
	{ echo x; sleep 0.2; echo x; } |
		timeout 5 socat -u - "$address:127.0.0.1:$PORT,priority=$((PRIORITY + i))" 2>/dev/null
done
for _ in $(seq 20); do
	[ "$(dmesg_since | grep -c "skb hash: ")" -ge $((NFLOWS * DATAGRAMS)) ] && break
	sleep 0.5
done

lunatik stop "$SCRIPT"
out=$(dmesg_since)

# hashes <flow>: the hashes the hook printed for the flow's datagrams, one per line
hashes() {
	echo "$out" | sed -n "s/.*skb hash: $1 \([0-9]*\)$/\1/p"
}

# one <flow>: the flow's hash when its datagrams read one, nonzero, and nothing otherwise
one() {
	local h
	h=$(hashes "$1" | sort -u)
	[ "$(hashes "$1" | wc -l)" -eq "$DATAGRAMS" ] && [ "$(echo "$h" | wc -l)" -eq 1 ] &&
		[ "$h" != 0 ] && echo "$h"
}

if [ "$(hashes 1 | sort -u)" = 0 ] && [ "$(hashes 1 | wc -l)" -eq "$DATAGRAMS" ]; then
	ktap_pass "hash reads 0 on an unconnected socket's datagrams, which nothing hashed"
else
	ktap_fail "hash reads 0 on an unconnected socket's datagrams, which nothing hashed"
	comment "flow 1 read: $(hashes 1 | tr '\n' ' ')"
fi

h2=$(one 2)
h3=$(one 3)
if [ -n "$h2" ] && [ -n "$h3" ]; then
	ktap_pass "hash reads one nonzero hash on each datagram of a connected socket"
else
	ktap_fail "hash reads one nonzero hash on each datagram of a connected socket"
	comment "flow 2 read: $(hashes 2 | tr '\n' ' '), flow 3 read: $(hashes 3 | tr '\n' ' ')"
fi

if [ -n "$h2" ] && [ -n "$h3" ] && [ "$h2" != "$h3" ]; then
	ktap_pass "hash reads two connected sockets apart"
else
	ktap_fail "hash reads two connected sockets apart"
	comment "flow 2 read: ${h2:-none}, flow 3 read: ${h3:-none}"
fi

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

