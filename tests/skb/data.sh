#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests where skb:data() views end in a netfilter hook, and what "mac" refuses.
#
# A ping over an ipip tunnel reaches LOCAL_OUT twice. The inner packet has no MAC header
# yet, and "mac" refuses it with "MAC header not set". The outer packet has its MAC header
# at the inner IPv4 header, past skb->data by the outer header: its "net" view is as long as
# the packet and its "mac" view is shorter by the outer header, both ending at the tail.
# The hook then trims that packet below the outer header with skb:resize, where "mac"
# refuses it with "MAC header past the tail", and drops it. The hook never reads a "mac"
# view, so a build without the refusals fails the cases with no out-of-bounds access. The
# tunnel runs over loopback and needs only the ipip module; the cases skip without it.
#
# Usage: sudo bash tests/skb/data.sh

SCRIPT="tests/skb/data"
TUNNEL="lunatikip0"
LOCAL="127.0.0.1"
REMOTE="127.0.0.2"
INNER="10.199.0.1"
PEER="10.199.0.2"
MARK=1278 # MARK in data.lua
TAIL="data: a netfilter view ends at the packet's tail"
UNSET="data: \"mac\" refuses a packet whose MAC header is not set"
PAST="data: \"mac\" refuses a MAC header past the tail"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

IPIP_LOADED=0
cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip link del "$TUNNEL" 2>/dev/null
	[ "$IPIP_LOADED" = 1 ] && modprobe -r ipip 2>/dev/null
}
trap cleanup EXIT
cleanup

verdict() {
	local cell="$1" title="$2"
	local failed=$(echo "$out" | grep -o "skb data: $cell FAIL.*" | head -1)
	if [ -n "$failed" ]; then
		ktap_fail "$title: $failed"
	elif echo "$out" | grep -q "skb data: $cell ok"; then
		ktap_pass "$title"
	else
		ktap_fail "$title: the hook never reached it"
	fi
}

ktap_header
ktap_plan 3

lsmod | grep -q "^ipip " || { modprobe ipip 2>/dev/null && IPIP_LOADED=1; }
if ! ip link add "$TUNNEL" type ipip local "$LOCAL" remote "$REMOTE" 2>/dev/null; then
	echo "# SKIP: ipip unavailable"
	ktap_skip "$TAIL"
	ktap_skip "$UNSET"
	ktap_skip "$PAST"
	ktap_totals
	exit 0
fi
ip addr add "$INNER/32" dev "$TUNNEL"
ip link set "$TUNNEL" up
ip route add "$PEER/32" dev "$TUNNEL"

mark_dmesg
run_script --context=softirq "$SCRIPT"
ping -c 1 -W 1 -m "$MARK" -I "$TUNNEL" "$PEER" > /dev/null 2>&1
lunatik stop "$SCRIPT" 2>/dev/null

out=$(dmesg_since)
check_dmesg || { ktap_totals; exit 1; }
verdict tail "$TAIL"
verdict unset "$UNSET"
verdict past "$PAST"
ktap_totals

