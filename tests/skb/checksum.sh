#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests skb:checksum on packets whose IP length fits them and on packets whose IP length does not.
#
# A LOCAL_OUT netfilter hook takes the first data packet of each sender, picked by its
# SO_PRIORITY, and calls checksum() on it. A TCP segment over 127.0.0.1 and a UDP datagram over
# ::1, their checksum fields zeroed, are summed: the IPv4 header sums to 0, and each segment
# verifies against its pseudo-header. A TCP segment whose tot_len is one byte short of its header,
# a TCP segment and a UDP datagram shrunk with skb:resize, whose IP length then runs past their
# end, and a UDP datagram carrying a destination options header, whose payload_len counts that
# header past where the UDP sum starts, are left unchanged byte for byte, as are a TCP segment
# shrunk to 30 bytes with its tot_len rewritten to fit, which no longer holds its check field, and
# one whose IHL reads 4, below the 5 ip_rcv_core requires; a build without those refusals rewrites
# the IPv4 header checksum of both. A UDP datagram over ::1 whose first payload word makes its sum
# fold to 0 gets the check field 0xffff, CSUM_MANGLED_0, where a build that stores the sum as it
# comes leaves 0, which an IPv6 receiver drops. The hook drops every packet it takes; TCP resends
# it untouched, and the UDP send fails with EPERM, so the senders' errors are discarded.
#
# A luaskb that sums a length past the packet ends skb_checksum on BUG_ON and panics the host, and
# its check has no symbol or message of its own. The packets past their end are therefore sent
# only once the loaded luaskb left the packet whose length falls short of its header unchanged: a
# build without the check sums that one too, and survives it where csum_partial survives a negative
# length, since skb_checksum hands it whole to csum_partial and returns before its BUG_ON.
# csum_partial returns 0 for it on arm64 and riscv and sums 63 bytes of the segment on x86_64; on
# ppc64 and s390 it reads it as a huge length. The IPv6 cases skip where lo has no ::1.
#
# The priorities are outside 0..6, which only a process with CAP_NET_ADMIN or CAP_NET_RAW may set,
# so no other process on the host picks a case.
#
# Usage: sudo bash tests/skb/checksum.sh

SCRIPT="tests/skb/checksum"
PORT=5567
PAYLOAD=256              # PAYLOAD in checksum.lua
PRIORITY=$((0x12370000)) # PRIORITY in checksum.lua
FITS="fits4 fits6"
GATE="below4"
PAST="past4 past6 ext6 short4 ihl4"
ZERO="zero6"
CASES="$FITS $GATE $PAST $ZERO" # in the order of pending in checksum.lua
DSTOPTS="41:59:x0000010400000000" # IPPROTO_IPV6, IPV6_DSTOPTS: an 8-byte header holding one PadN
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
	for c in $CASES; do ktap_skip "checksum $c — socat unavailable"; done
	ktap_skip "no Lua errors, kernel warnings or oopses — socat unavailable"
	ktap_totals
	exit 0
fi

ipv6=1
ip -6 addr show dev lo 2>/dev/null | grep -q "inet6 ::1/" || ipv6=0

declare -A skip
sent=0

# send <case>...: a PAYLOAD-byte packet for each case named, at the case's priority, then the
# hook's lines for every packet sent so far
send() {
	local i=0 target
	for c in $CASES; do
		i=$((i + 1))
		case " $* " in *" $c "*) ;; *) continue ;; esac
		target="TCP:127.0.0.1:$PORT"
		case $c in *6)
			[ "$ipv6" = 1 ] || { skip[$c]="lo has no ::1"; continue; }
			target="UDP6:[::1]:$PORT" ;;
		esac
		[ "$c" = ext6 ] && target="$target,setsockopt=$DSTOPTS"
		head -c "$PAYLOAD" /dev/zero | tr '\0' x |
			timeout 5 socat -u - "$target,priority=$((PRIORITY + i))" 2>/dev/null
		sent=$((sent + 1))
	done
	for _ in $(seq 20); do
		[ "$(dmesg_since | grep -c "skb checksum: ")" -ge "$sent" ] && break
		sleep 0.5
	done
}

mark_dmesg
run_script --context=softirq "$SCRIPT"

socat -u "TCP-LISTEN:$PORT,reuseaddr,fork" OPEN:/dev/null &
LISTENER=$!
for _ in $(seq 20); do [ -n "$(ss -tHln "sport = :$PORT" 2>/dev/null)" ] && break; sleep 0.1; done

send $FITS $GATE $ZERO
if dmesg_since | grep -q "skb checksum: $GATE ok"; then
	send $PAST
else
	for c in $PAST; do
		skip[$c]="$GATE did not come back unchanged, so a length past the packet may panic the host"
	done
fi

lunatik stop "$SCRIPT"
out=$(dmesg_since)

for c in $CASES; do
	if [ -n "${skip[$c]}" ]; then
		ktap_skip "checksum $c — ${skip[$c]}"
	elif echo "$out" | grep -q "skb checksum: $c ok"; then
		ktap_pass "checksum $c"
	else
		ktap_fail "checksum $c"
		comment "$(echo "$out" | grep "skb checksum: $c" || echo "no hook output")"
	fi
done

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

