#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that the mark a compiled TC program sets is the one the netfilter rules after it read: the
# program, which sets skb:mark(PASSED) on every packet and lets it through, is attached by
# `lunatik run --dev` at the tcx ingress of a bridge's port, a veth whose peer sits in a network
# namespace, and a rule of an nft bridge table at prerouting counts the echo requests that carry
# PASSED. __netif_receive_skb_core runs sch_handle_ingress, where tcx runs, before the bridge's
# rx_handler, and br_handle_frame runs the NF_BR_PRE_ROUTING hooks on the same skb
# (net/core/dev.c, net/bridge/br_input.c, read at 6.6 and 6.8).
#   - PINGS pings from the namespace to the bridge's address are answered, and the rule counts
#     PINGS echo requests, where a program that set no mark, or another field, leaves it at 0
# Skips without nft, on a kernel whose configuration lacks a bridge, nftables' bridge family or
# tcx, and where the CLI's loader names a libbpf older than tcx.
#
# Usage: sudo bash tests/luaebpf/mark.sh

BRIDGE="luaebpfbr0"
NETNS="lunatik_luaebpfmark"
TABLE="lunatik_luaebpf"
HOST="10.197.1.1"
TARGET="10.197.1.2"
PASSED=2 # PASSED in mark.bpf.lua
PINGS=3
NOTCX="tcx needs libbpf 1.3.0" # lualoader_open, luaebpf/loader.c
OPTIONS="CONFIG_BRIDGE CONFIG_NF_TABLES_BRIDGE CONFIG_NET_XGRESS"
TITLE="luaebpf: a netfilter rule after a TC program at tcx ingress counts the packets it marked"

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="mark"

# common.sh's cleanup, which stops the run and deletes the port, and the table, the namespace and
# the bridge the case adds
teardown() {
	cleanup
	nft delete table bridge "$TABLE" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$BRIDGE" 2>/dev/null
	return 0
}

# the packets the rule counted
counted() {
	nft list chain bridge "$TABLE" prerouting | grep -oP 'packets \K[0-9]+'
}

trap teardown EXIT
teardown

luaebpf_start 1

command -v nft >/dev/null || skip_script "luaebpf: nft is not installed"
option=$(lacking $OPTIONS) && skip_script "luaebpf: the kernel lacks $option"
output=$(luaebpf_stage mark) || { comment "$output"; fail "luaebpf: mark.bpf.lua did not compile"; }

ip netns add "$NETNS"
ip link add "$BRIDGE" type bridge || fail "luaebpf: the case could not create a bridge"
ip link add "$LUAEBPF_DEV" type veth peer name "$LUAEBPF_PEER"
ip link set "$LUAEBPF_PEER" netns "$NETNS"
ip link set "$LUAEBPF_DEV" master "$BRIDGE"
ip addr add "$HOST/24" dev "$BRIDGE"
ip link set "$BRIDGE" up
ip link set "$LUAEBPF_DEV" up
ip netns exec "$NETNS" ip addr add "$TARGET/24" dev "$LUAEBPF_PEER"
ip netns exec "$NETNS" ip link set "$LUAEBPF_PEER" up

{ nft add table bridge "$TABLE" &&
	nft add chain bridge "$TABLE" prerouting '{ type filter hook prerouting priority 0 ; }' &&
	nft add rule bridge "$TABLE" prerouting icmp type echo-request meta mark "$PASSED" counter; } ||
	fail "luaebpf: the case could not add its nft rule"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/mark 2>&1)
status=$?
grep -qF "$NOTCX" <<< "$output" && skip_script "luaebpf: $NOTCX"
ip netns exec "$NETNS" ping -c "$PINGS" -i 0.2 -W 1 "$HOST" > /dev/null 2>&1
answered=$?
packets=$(counted)
teardown

if [ "$status" -ne 0 ] || [ -n "$output" ]; then
	comment "$output"
	ktap_fail "$TITLE: the run exited $status"
elif [ "$answered" -ne 0 ]; then
	ktap_fail "$TITLE: the namespace's pings were not answered"
elif [ "$packets" != "$PINGS" ]; then
	ktap_fail "$TITLE: the rule counted '${packets:-nothing}' marked echo requests, not $PINGS"
else
	ktap_pass "$TITLE"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

