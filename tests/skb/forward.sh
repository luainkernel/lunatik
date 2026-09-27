#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests where skb:forward() in a netfilter hook refuses a packet and where it sends a clone.
#
# A ping over an ipip tunnel reaches LOCAL_OUT with the outer packet's MAC header at the inner
# IPv4 header, past skb->data by the outer header: forward() refuses it with "MAC header past
# the data", and the hook drops it. A ping to the loopback address reaches PRE_ROUTING on lo
# with its MAC header before skb->data: forward() sends a clone back out through lo, and the
# hook sees the clone arrive. The tunnel's remote end is its local one, so a second ping over it
# comes back decapsulated to PRE_ROUTING on the tunnel with its MAC header at skb->data:
# forward() sends a clone back into the tunnel, and the hook sees that one arrive too. That hook
# counts echo requests only, since an echo reply carries the ping's mark where
# net.ipv4.fwmark_reflect is set and would pass for the clone. The tunnel runs over loopback and
# needs only the ipip module; its cases skip without it. A luaskb without the refusal pushes the
# clone below its head and panics the host, so the tunnel's cases also skip unless the loaded
# luaskb is the installed one and the installed one carries the refusal.
#
# Usage: sudo bash tests/skb/forward.sh

SCRIPT="tests/skb/forward"
MODULE="luaskb"
REFUSAL="MAC header past the data" # REFUSAL in forward.lua
TUNNEL="lunatikfwd0"
LOCAL="127.0.0.1"
INNER="10.199.1.1"
PEER="10.199.1.2"
PAST_MARK=1291   # PAST_MARK in forward.lua
BEFORE_MARK=1292 # BEFORE_MARK in forward.lua
AT_MARK=1293     # AT_MARK in forward.lua
PAST="forward: refuses a MAC header past the data"
BEFORE="forward: sends a clone when the MAC header precedes the data"
AT="forward: sends a clone when the MAC header is at the data"

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
	local failed=$(echo "$out" | grep -o "skb forward: $cell FAIL.*" | head -1)
	if [ -n "$failed" ]; then
		ktap_fail "$title: $failed"
	elif echo "$out" | grep -q "skb forward: $cell ok"; then
		ktap_pass "$title"
	else
		ktap_fail "$title: the hook never reached it"
	fi
}

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_skip "$PAST"
	ktap_skip "$AT"
	ktap_skip "$BEFORE"
	ktap_totals
	exit 0
}

skip=""
if [ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" != "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] ||
	! grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"; then
	skip="the loaded $MODULE does not carry the refusal: forward() would panic the host"
else
	lsmod | grep -q "^ipip " || { modprobe ipip 2>/dev/null && IPIP_LOADED=1; }
	ip link add "$TUNNEL" type ipip local "$LOCAL" remote "$LOCAL" 2>/dev/null || skip="ipip unavailable"
fi
if [ -z "$skip" ]; then
	ip addr add "$INNER/32" dev "$TUNNEL"
	ip link set "$TUNNEL" up
	ip route add "$PEER/32" dev "$TUNNEL"
fi

mark_dmesg
run_script --context=softirq "$SCRIPT"
if [ -z "$skip" ]; then
	for mark in "$PAST_MARK" "$AT_MARK"; do
		ping -c 1 -W 1 -m "$mark" -I "$TUNNEL" "$PEER" > /dev/null 2>&1
	done
fi
ping -c 1 -W 1 -m "$BEFORE_MARK" "$LOCAL" > /dev/null 2>&1
lunatik stop "$SCRIPT" 2>/dev/null

out=$(dmesg_since)
check_dmesg || { ktap_totals; exit 1; }
if [ -n "$skip" ]; then
	echo "# SKIP: $skip"
	ktap_skip "$PAST"
	ktap_skip "$AT"
else
	verdict past "$PAST"
	verdict at "$AT"
fi
verdict before "$BEFORE"
ktap_totals

