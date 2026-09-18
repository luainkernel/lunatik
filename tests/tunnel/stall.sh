#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a relay whose destination stopped reading can still be stopped.
# The peer locks a small receive buffer on the far end of the relay's send,
# never reads it, and pushes until its own bounded sends stop making progress;
# the relay is then inside a send it cannot finish on every pass, which
# /proc/<tid>/stack shows as sk_stream_wait_memory under luasocket_send. It
# asserts that it did stall, and the shell asserts the relay had not ended, so
# the measured stop is taken with the relay holding an undeliverable remainder.
#
# What returns that send here is not the SO_SNDTIMEO tunnel.body installs: from
# 6.1 kthread_stop raises TIF_NOTIFY_SIGNAL (kernel/kthread.c), which the
# signal_pending check in sk_stream_wait_memory (net/core/stream.c) reads, so
# the send ends whether or not it was bounded. Below 6.1 there is no such flag
# and wait_woken returns its timeout unchanged once the thread is asked to stop
# (kernel/sched/wait.c), so current_timeo stops decrementing and the !*timeo_p
# exit is never reached: the bound ends that wait no more than the missing
# signal does. The first case therefore pins the property and not the mechanism,
# and nothing in it discriminates on the bound; what the bound does buy is
# bounded.sh's, where a stalled direction leaves the other one moving.
#
# That signal ends the send with EINTR and nothing copied, which is the stop and
# not a failure: the second case is that the body returns from it rather than
# propagating it, its end-of-relay marker being printed after tunnel.body's
# return and so absent from a relay that died there. The relay of this test takes
# a send bound two hundred times the idle yield, so the stop lands inside the
# send and not between two of them; a raise out of a thread body reaches dmesg as
# the bare errno luathread logs, which KTAP_ERRORS does not match.
#
# Usage: sudo bash tests/tunnel/stall.sh

SCRIPT="tests/tunnel/stall"
PEER="tests/tunnel/stall_peer"
MODULE="luasocket"

# what a stop must beat while the relay holds an undeliverable remainder
STOPBOUND=1000

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$PEER" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

CASES=(
	"stall: a stop returns while the relay holds bytes the destination will not take"
	"stall: the relay ends on that stop instead of raising what interrupted its send"
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
comment "$(dmesg_since | grep -o "tunnel stall: .*")"
dmesg_since | grep -q "tunnel stall: the destination stopped taking bytes" ||
	fail "${CASES[0]}: the peer never filled the path"
dmesg_since | grep -q "tunnel stall: relay ended" &&
	fail "${CASES[0]}: the relay ended before it was stalled"

started=$(date +%s%N)
lunatik stop "$SCRIPT" > /dev/null 2>&1
elapsed=$(( ($(date +%s%N) - started) / 1000000 ))
lunatik stop "$PEER" > /dev/null 2>&1
comment "stop returned in $elapsed ms"
check_dmesg || { ktap_totals; exit 1; }
[ "$elapsed" -lt "$STOPBOUND" ] || fail "${CASES[0]}: stop took $elapsed ms"
running=$(lunatik list)
case "$running" in *tunnel*) fail "${CASES[0]}: lunatik list says $running";; esac
ktap_pass "${CASES[0]}"

dmesg_since | grep -q "tunnel stall: relay ended" ||
	fail "${CASES[1]}: the relay did not return from the send the stop interrupted"
ktap_pass "${CASES[1]}"

ktap_totals

