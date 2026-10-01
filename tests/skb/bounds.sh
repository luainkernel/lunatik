#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that skb:mark and skb:priority take a value of the 32 bits each field holds
# and refuse one past them as out of bounds, instead of storing its low bits.
#
# A LOCAL_OUT netfilter hook takes the first UDP datagram to PORT and, for each
# accessor, sets 0 and 0xffffffff and reads each back, then sets a known value and
# asks for -1, 2^32 and 2^32 plus that value: each raises "out of bounds" and the
# field still reads the known value. A truncating build takes the last one as the
# known value itself, so it answers with no error rather than the refusal.
#
# Usage: sudo bash tests/skb/bounds.sh

SCRIPT="tests/skb/bounds"
PORT=5566 # PORT in bounds.lua
ACCESSORS="mark priority"
NACCESSORS=$(echo $ACCESSORS | wc -w)

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $((NACCESSORS + 1))

mark_dmesg
run_script --context=softirq "$SCRIPT"

echo x > "/dev/udp/127.0.0.1/$PORT" 2>/dev/null
for _ in $(seq 20); do
	[ "$(dmesg_since | grep -c "skb bounds: ")" -ge "$NACCESSORS" ] && break
	sleep 0.5
done

lunatik stop "$SCRIPT"
out=$(dmesg_since)

for a in $ACCESSORS; do
	if echo "$out" | grep -q "skb bounds: $a ok"; then
		ktap_pass "skb:$a takes 32 bits and refuses a value past them"
	else
		ktap_fail "skb:$a takes 32 bits and refuses a value past them"
		comment "$(echo "$out" | grep "skb bounds: $a" || echo "no hook output")"
	fi
done

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

