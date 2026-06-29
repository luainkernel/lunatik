#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.channel end to end FROM SOFTIRQ: a softirq runtime registers a
# generic netlink family ("lunatiktest"), unicasts to an absent port id (which
# must return false), and installs a PRE_ROUTING netfilter hook that, on
# received traffic (NET_RX softirq), both broadcasts to the group and unicasts
# to a fixed port id. A userspace subscriber (built with gcc) binds to that port
# id and joins the group, and receives both messages, proving kernel-to-
# userspace broadcast and unicast delivery from softirq.
#
# Usage: sudo bash tests/netlink/channel.sh

SCRIPT="tests/netlink/channel"
MODULE="luanetlink"
FAMILY="lunatiktest"
DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SUB_BIN="$(mktemp)"
SUB_OUT="$(mktemp)"
SUB_ERR="$(mktemp)"
cleanup() {
	kill "$SUB_PID" 2>/dev/null
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -f "$SUB_BIN" "$SUB_OUT" "$SUB_ERR"
}
trap cleanup EXIT

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
command -v gcc  > /dev/null 2>&1 || skip "channel: gcc unavailable"
command -v genl > /dev/null 2>&1 || skip "channel: genl tool unavailable"

gcc -O2 -o "$SUB_BIN" "$DIR/channel_subscriber.c" 2>/dev/null || skip "channel: subscriber failed to build"

mark_dmesg
run_script "$SCRIPT" softirq
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "netlink channel: unicast to absent peer returns false" || fail "unicast did not return false"
ktap_pass "channel: unicast to an absent port id returns false"

# the family is now registered; resolve its multicast group id (the group line
# is the only one with an "ID-0x" token; the family id prints as "ID: 0x")
GRP=$(genl ctrl get name "$FAMILY" 2>/dev/null \
	| grep -oiE 'ID-0x[0-9a-fA-F]+' | head -1 | sed 's/^[Ii][Dd]-//')
[ -n "$GRP" ] || fail "could not resolve multicast group for family $FAMILY"

"$SUB_BIN" "$GRP" > "$SUB_OUT" 2> "$SUB_ERR" &
SUB_PID=$!
ready=""
for _ in $(seq 1 50); do grep -q READY "$SUB_ERR" 2>/dev/null && { ready=1; break; }; sleep 0.1; done
[ -n "$ready" ] || fail "subscriber not ready: $(cat "$SUB_ERR")"

# generate loopback traffic; the received packet fires PRE_ROUTING in NET_RX softirq
for _ in $(seq 1 5); do echo x > /dev/udp/127.0.0.1/9999 2>/dev/null; sleep 0.1; done

wait "$SUB_PID" 2>/dev/null
check_dmesg || { ktap_totals; exit 1; }

grep -q "channel broadcast ok" "$SUB_OUT" || fail "subscriber did not receive the softirq broadcast"
ktap_pass "channel: userspace received a broadcast sent from a softirq hook"

grep -q "channel unicast ok" "$SUB_OUT" || fail "subscriber did not receive the softirq unicast"
ktap_pass "channel: userspace received a unicast sent from a softirq hook"

ktap_totals

