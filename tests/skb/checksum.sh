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
# and a TCP segment and a UDP datagram shrunk with skb:resize, whose IP length then runs past their
# end, are left unchanged byte for byte. The hook drops every packet it takes; TCP resends it
# untouched, and the UDP send fails with EPERM, so the senders' errors are discarded.
#
# A luaskb that sums a length past the packet ends skb_checksum on BUG_ON and panics the host, and
# its check has no symbol or message of its own. The shrunk packets are therefore sent only once
# the loaded luaskb left the packet whose length falls short of its header unchanged: a build
# without the check sums that one too, and survives it, since skb_checksum handed a negative
# length sums nothing and returns. The IPv6 cases skip where lo has no ::1.
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
PAST="past4 past6"
CASES="$FITS $GATE $PAST" # in the order of pending in checksum.lua
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

send $FITS $GATE
if dmesg_since | grep -q "skb checksum: $GATE ok"; then
	send $PAST
else
	for c in $PAST; do
		skip[$c]="the loaded luaskb sums a length short of the header, so a length past the packet would panic the host"
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

