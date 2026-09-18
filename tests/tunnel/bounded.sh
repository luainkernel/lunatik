#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what bounding the send buys the relay, which stall.sh cannot pin
# because from 6.1 the stop is returned by a signal and not by the bound: a
# destination that stopped reading costs one pass and not the relay. The relay
# here accepts its ends from a listener whose small SO_RCVBUF and SO_SNDBUF
# they inherit, so the whole path holds tens of kilobytes; the peer fills it,
# which leaves the relay inside a send it cannot finish on every pass, and then
# reads the other direction. An unbounded send would still be sitting in
# sk_stream_wait_memory, so move() would never reach the second direction and
# nothing would come back.
#
# The second case is the remainder: a bounded send is a short send, and what it
# could not deliver is pending for that direction until the next pass takes it.
# The peer drains the far end and the counts are compared, which catches a
# remainder dropped and a remainder sent twice; the payload is one repeated
# byte, so the count is the assertion and not the bytes. The third case reads
# that remainder through opts.transform: the relay's hook counts the bytes it
# was handed from the stalled direction, and the total is what the peer pushed,
# a payload being transformed once and the tail a short send left behind not
# put through it again. The fourth case is the options a bound rests on: a
# timeout that is not positive is refused where it arrives, since SO_SNDTIMEO
# reads a zero as no bound at all and a negative as no wait at all; so is a
# size that is not positive, since a receive of no bytes answers an empty
# string, which the relay reads as the peer's orderly close and ends on.
#
# Usage: sudo bash tests/tunnel/bounded.sh

SCRIPT="tests/tunnel/bounded"
PEER="tests/tunnel/bounded_peer"
REFUSE="tests/tunnel/bounded_refuse"
MODULE="luasocket"

# the reverse payload tests/tunnel/pair.lua sends, as the exact bytes
BTOA="bravo to alpha"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$REFUSE" > /dev/null 2>&1
	lunatik stop "$PEER" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

CASES=(
	"bounded: a stalled direction leaves the other one moving"
	"bounded: the remainder a short send left behind is delivered"
	"bounded: the remainder is not put through the transform a second time"
	"bounded: an option that is not positive is refused"
)

ktap_header
ktap_plan ${#CASES[@]}

skip_all()
{
	echo "# SKIP: $1"
	for c in "${CASES[@]}"; do ktap_skip "$c"; done
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"

mark_dmesg
out=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$out" ] || fail "${CASES[0]}: lunatik spawn said: $out"
run_script "$PEER"
comment "$(dmesg_since | grep -o "tunnel bounded: the destination stopped taking bytes after .*")"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "tunnel bounded: the destination stopped taking bytes" ||
	fail "${CASES[0]}: the peer never filled the path"
dmesg_since | grep -q "tunnel bounded: A read $BTOA$" ||
	fail "${CASES[0]}: nothing came back while the other direction was stalled"
ktap_pass "${CASES[0]}"

read -r drained pushed <<< "$(dmesg_since |
	sed -n 's/.*tunnel bounded: B read \([0-9]*\) of \([0-9]*\)$/\1 \2/p' | tail -n 1)"
comment "the relay delivered ${drained:-no} of the ${pushed:-?} bytes it took off A"
[ -n "$drained" ] && [ "$drained" = "$pushed" ] ||
	fail "${CASES[1]}: the far end read $drained of $pushed bytes"
ktap_pass "${CASES[1]}"

# the total reaches dmesg when the body returns, so the relay is stopped first
lunatik stop "$SCRIPT" > /dev/null 2>&1
counted=$(dmesg_since | sed -n 's/.*tunnel bounded: the transform saw \([0-9]*\) bytes$/\1/p' | tail -n 1)
comment "the transform saw ${counted:-no} of the ${pushed:-?} bytes the relay took off A"
[ -n "$counted" ] && [ "$counted" = "$pushed" ] ||
	fail "${CASES[2]}: the transform saw $counted of $pushed bytes"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "${CASES[2]}"

mark_dmesg
run_script "$REFUSE"
dmesg_since | grep -q "tunnel bounded: an option that is not positive is refused" ||
	fail "${CASES[3]}"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "${CASES[3]}"

ktap_totals

