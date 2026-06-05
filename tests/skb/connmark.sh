#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests skb:connmark (conntrack mark get/set).
#
# connmark(value) overwrites and returns the new mark; connmark() reads it; masked
# updates are composed in Lua. A LOCAL_OUT netfilter hook exercises, on a tracked
# UDP flow, an overwrite, a masked set that preserves out-of-mask bits, and a
# clear; the final mark (0xba000000) is cross-checked from userspace with
# `conntrack -L`, mirroring how tc act_ctinfo reads ct->mark. A second, notrack'd
# flow checks that connmark returns nil (read and write) when there is no conntrack.
#
# Conntrack is engaged via an nft `ct state` rule; the test skips cleanly if
# nf_conntrack is unavailable.
#
# Usage: sudo bash tests/skb/connmark.sh

SCRIPT="tests/skb/connmark"
PORT=5562
PORT_NOTRACK=5563
MARK=0xba000000   # DSCP_VAL in connmark.lua; conntrack -L prints it in decimal

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

NFT_TABLE="lunatik_connmark"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	nft delete table ip "$NFT_TABLE" 2>/dev/null
	conntrack -D -p udp --dport "$PORT" >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

# The tests are unrunnable without conntrack: skip cleanly, don't fail.
skip_all() {
	ktap_skip "connmark get/set masked update — $*"
	ktap_skip "connmark visible in conntrack table — $*"
	ktap_skip "no-conntrack returns — $*"
	ktap_totals
	exit 0
}

ktap_header
ktap_plan 3
mark_dmesg

modprobe nf_conntrack 2>/dev/null
nft add table ip "$NFT_TABLE" 2>/dev/null
# notrack the no-conntrack test port (raw chain runs before conntrack)
nft add chain ip "$NFT_TABLE" raw '{ type filter hook output priority -300 ; }' 2>/dev/null
nft add rule ip "$NFT_TABLE" raw udp dport $PORT_NOTRACK notrack 2>/dev/null
# engage conntrack for everything else
nft add chain ip "$NFT_TABLE" c '{ type filter hook output priority -100 ; }' 2>/dev/null
nft add rule ip "$NFT_TABLE" c ct state new counter 2>/dev/null || skip_all "conntrack unavailable on host"

run_script "$SCRIPT" softirq

# One datagram to each port (no listener needed).
echo x > "/dev/udp/127.0.0.1/$PORT" 2>/dev/null
echo x > "/dev/udp/127.0.0.1/$PORT_NOTRACK" 2>/dev/null
sleep 1

out=$(dmesg_since)

# 1) overwrite + Lua-composed masked update on a tracked flow (set + preservation + clear).
if echo "$out" | grep -q "connmark: tracked ok"; then
	ktap_pass "connmark overwrite + Lua-composed masked update (set/preserve/clear)"
elif echo "$out" | grep -q "connmark: tracked FAIL"; then
	fail "masked update: $(echo "$out" | grep -oE 'connmark: tracked FAIL [a-z]+' | head -1)"
elif echo "$out" | grep -q "attempt to call a nil value"; then
	skip_all "skb:connmark unavailable (built without CONFIG_NF_CONNTRACK_MARK?)"
else
	fail "no hook output for tracked flow"
fi

# 2) userspace cross-check of the final mark, as tc act_ctinfo would read it.
if conntrack -L 2>/dev/null | grep -qE "dport=$PORT\b.*mark=$((MARK))\b"; then
	ktap_pass "connmark visible in conntrack table (mark=$MARK)"
else
	fail "connmark not found in conntrack table"
fi

# 3) no-conntrack: connmark returns nil for read and write (notrack'd flow).
if echo "$out" | grep -q "connmark: notrack ok"; then
	ktap_pass "connmark returns nil without conntrack"
else
	fail "no-conntrack returns wrong: $(echo "$out" | grep -oE 'connmark: notrack [A-Za-z]+' | head -1)"
fi

check_dmesg || { ktap_totals; exit 1; }
ktap_totals

