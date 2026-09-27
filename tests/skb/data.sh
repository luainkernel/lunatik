#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests where skb:data() views end in a netfilter hook, that its "net" and "mac" views are two,
# and what "mac" refuses.
#
# A ping to the loopback address reaches LOCAL_OUT with no MAC header yet, and "mac" refuses
# it with "MAC header not set"; it then reaches PRE_ROUTING on lo with its MAC header before
# skb->data, where the "mac" view is longer than the packet by the Ethernet header. A ping
# over an ipip tunnel reaches LOCAL_OUT twice, the inner packet refused as the loopback one
# is. The outer packet has its MAC header at the inner IPv4 header, past skb->data by the
# outer header: its "net" view is as long as the packet and its "mac" view is shorter by the
# outer header, both ending at the tail.
# Taken together, the two views stay two: the "net" view taken first keeps its length and still
# reads the outer header's protocol after the "mac" view is taken, on the packet and on a copy
# of it. The hook then trims that packet below the outer header with skb:resize, where "mac"
# refuses it with "MAC header past the tail", and drops it. A second tunnel ping's first
# callback finds the two views the outer packet's callback took with length 0, and, after a
# full collection, the two views of the copy it dropped too; it reads their lengths alone, so a
# build that leaves one set after the callback or the copy fails with no read of the packet it
# viewed. The hooks never read a "mac" view, so a build without the refusals fails the cases
# with no out-of-bounds access. The tunnel runs over loopback and needs only the ipip module;
# its cases skip without it.
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
LAYERS="data: the \"net\" and \"mac\" views of one skb are two views"
COPY="data: the \"net\" and \"mac\" views of a copy are two views"
CLEARED="data: the views of a hook's skb have length 0 once its callback returns"
COLLECTED="data: the \"net\" and \"mac\" views of a copy have length 0 once the copy is collected"
UNSET="data: \"mac\" refuses a packet whose MAC header is not set"
RECEIVED="data: a received frame's \"mac\" view starts at its MAC header"
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
ktap_plan 8

skip=""
lsmod | grep -q "^ipip " || { modprobe ipip 2>/dev/null && IPIP_LOADED=1; }
if ip link add "$TUNNEL" type ipip local "$LOCAL" remote "$REMOTE" 2>/dev/null; then
	ip addr add "$INNER/32" dev "$TUNNEL"
	ip link set "$TUNNEL" up
	ip route add "$PEER/32" dev "$TUNNEL"
else
	skip="ipip unavailable"
fi

mark_dmesg
run_script --context=softirq "$SCRIPT"
ping -c 1 -W 1 -m "$MARK" "$LOCAL" > /dev/null 2>&1
[ -z "$skip" ] && ping -c 2 -i 0.2 -W 1 -m "$MARK" -I "$TUNNEL" "$PEER" > /dev/null 2>&1
lunatik stop "$SCRIPT" 2>/dev/null

out=$(dmesg_since)
check_dmesg || { ktap_totals; exit 1; }
verdict unset "$UNSET"
verdict received "$RECEIVED"
if [ -n "$skip" ]; then
	echo "# SKIP: $skip"
	ktap_skip "$TAIL"
	ktap_skip "$LAYERS"
	ktap_skip "$COPY"
	ktap_skip "$CLEARED"
	ktap_skip "$COLLECTED"
	ktap_skip "$PAST"
else
	verdict tail "$TAIL"
	verdict layers "$LAYERS"
	verdict copy "$COPY"
	verdict cleared "$CLEARED"
	verdict collected "$COLLECTED"
	verdict past "$PAST"
fi
ktap_totals

