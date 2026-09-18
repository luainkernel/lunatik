#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the tunnel module between two plain sockets, which is the shape every
# other case in this suite is a variant of: a spawned relay accepts both ends of
# a loopback listener and a peer script holds the two far ends, so a payload
# written on one far end comes back out of the other.
#
# The stoppability cases are the ones that earn the suite: stop is measured and
# the elapsed milliseconds are printed, the way tests/tls/bounded_recv.sh prints
# its waits, since a body that does not come back round its loop is one
# kthread_stop waits on, and the number is the proof rather than the absence of
# a hang. A second spawn after that stop proves the port and the name came back,
# closing a peer proves the relay ends on the zero-length read rather than
# spinning on it, and a softirq runtime is refused before a socket of the
# relay's exists.
#
# Usage: sudo bash tests/tunnel/plain.sh

SCRIPT="tests/tunnel/plain"
PEER="tests/tunnel/plain_peer"
MODULE="luasocket"

# the payloads tests/tunnel/pair.lua sends, asserted here as the exact bytes
ATOB="alpha to bravo"
BTOA="bravo to alpha"

# what a stop must beat: the relay yields 10 ms when idle and bounds each send
# at 100 ms, so a stop that takes a second is not a bounded call returning
STOPBOUND=1000
# the shell's patience for the end-of-file the relay reads within one idle pass
ENDTRIES=20
ENDPOLL=0.1

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$PEER" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

CASES=(
	"plain: the relay carries a payload from A to B"
	"plain: the relay carries a payload from B to A"
	"plain: stop returns and leaves neither script running"
	"plain: a second spawn rebinds the port and relays again"
	"plain: the relay ends by itself when a peer closes"
	"plain: arming the relay in a softirq runtime is refused"
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

spawn_relay()
{
	local out
	out=$(lunatik spawn "$SCRIPT" 2>&1)
	[ -z "$out" ] || fail "$1: lunatik spawn said: $out"
}

roundtrip()
{
	spawn_relay "$1"
	run_script "$PEER"
	dmesg_since | grep -q "tunnel plain: B read $ATOB$" || fail "$1: nothing arrived on B"
	dmesg_since | grep -q "tunnel plain: A read $BTOA$" || fail "$1: nothing arrived on A"
}

mark_dmesg
roundtrip "${CASES[0]}"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "${CASES[0]}"
ktap_pass "${CASES[1]}"

# a relay stopped while both far ends are still open: every call it is inside of
# is a bounded one, so kthread_stop joins it
started=$(date +%s%N)
lunatik stop "$SCRIPT" > /dev/null 2>&1
elapsed=$(( ($(date +%s%N) - started) / 1000000 ))
lunatik stop "$PEER" > /dev/null 2>&1
comment "stop returned in $elapsed ms"
[ "$elapsed" -lt "$STOPBOUND" ] || fail "${CASES[2]}: stop took $elapsed ms"
running=$(lunatik list)
case "$running" in *tunnel*) fail "${CASES[2]}: lunatik list says $running";; esac
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "${CASES[2]}"

mark_dmesg
roundtrip "${CASES[3]}"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "${CASES[3]}"

# closing the peer's ends is the only stimulus here: the relay is left running
# and must end on the zero-length read by itself
mark_dmesg
lunatik stop "$PEER" > /dev/null 2>&1
ended=""
for _ in $(seq $ENDTRIES); do
	dmesg_since | grep -q "tunnel plain: relay ended" && { ended=yes; break; }
	sleep $ENDPOLL
done
# the verdict is read before the stop, since a stopped body prints that marker too
lunatik stop "$SCRIPT" > /dev/null 2>&1
[ -n "$ended" ] || fail "${CASES[4]}: the relay is still running"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "${CASES[4]}"

# the relay is a kernel thread over sleepable calls; a softirq runtime is
# refused at the listener, before anything of the relay is armed
mark_dmesg
out=$(lunatik spawn "$SCRIPT" softirq 2>&1)
case "$out" in
	*"process-context class in interrupt-context runtime"*) ;;
	*) fail "${CASES[5]}: lunatik spawn said: $out";;
esac
running=$(lunatik list)
case "$running" in *tunnel*) fail "${CASES[5]}: the refused spawn left $running running";; esac
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "${CASES[5]}"

ktap_totals

