#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A copy carries no skb extension, so its forward() refuses a packet its device encrypts by IPsec
# offload, and passes one the device sends as it is.
#
# A netdevsim port offloads an outbound ESP state in transport mode, set up as the kernel's own
# rtnetlink selftest sets one. A ping the state's policy covers reaches POST_ROUTING as the ESP
# packet that carries the state's xfrm_offload, which the port encrypts from: a copy's forward()
# raises "copy would leave unencrypted", where the packet's own forward() reaches the next refusal,
# "MAC header past the data", since the transport encapsulation leaves its MAC header at the IPv4
# protocol byte. A ping to an address no policy covers leaves the same port with no state, and a
# copy's forward() passes the refusal to raise "MAC header not set". The hook drops both packets.
# A build without the refusal fails the first case on the copy's "MAC header past the data". Skips
# without netdevsim or without its ESP offload.
#
# Usage: sudo bash tests/skb/copy_offload.sh

SCRIPT="tests/skb/copy_offload"
NSIM_ID=1320
SOURCE="10.199.8.1"
PEER="10.199.8.2"
OTHER="10.199.8.3"
SPI=0x1320
REQID=1320
ALGO="aead rfc4106(gcm(aes)) 0x3132333435363738393031323334353664636261 128"
OFFLOAD_MARK=1320 # OFFLOAD_MARK in copy_offload.lua
PLAIN_MARK=1321   # PLAIN_MARK in copy_offload.lua
OFFLOADED="copy_offload: a copy's forward() refuses a packet its device encrypts, the packet's own does not"
PLAIN="copy_offload: a copy's forward() passes the refusal on a packet the device sends as it is"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip xfrm policy delete dir out src "$SOURCE/32" dst "$PEER/32" 2>/dev/null
	ip xfrm state delete src "$SOURCE" dst "$PEER" proto esp spi "$SPI" 2>/dev/null
	nsim_del "$NSIM_ID"
}
trap cleanup EXIT
cleanup

skip_all() {
	echo "# SKIP: $1"
	ktap_skip "$OFFLOADED"
	ktap_skip "$PLAIN"
	ktap_skip "no Lua errors, kernel warnings or oopses"
	ktap_totals
	exit 0
}

verdict() {
	local cell="$1" title="$2"
	local failed=$(echo "$out" | grep -o "skb copy offload: $cell FAIL.*" | head -1)
	if [ -n "$failed" ]; then
		ktap_fail "$title: $failed"
	elif echo "$out" | grep -q "skb copy offload: $cell ok"; then
		ktap_pass "$title"
	else
		ktap_fail "$title: the hook never reached it"
	fi
}

ktap_header
ktap_plan 3

nsim_add "$NSIM_ID" || skip_all "no netdevsim"
IFACE=$(nsim_port "$NSIM_ID")
ip addr add "$SOURCE/24" dev "$IFACE"
ip link set "$IFACE" up
ip xfrm state add src "$SOURCE" dst "$PEER" proto esp spi "$SPI" mode transport reqid "$REQID" $ALGO \
	sel src "$SOURCE/32" dst "$PEER/32" offload dev "$IFACE" dir out 2>/dev/null ||
	skip_all "$IFACE offloads no ESP state"
ip xfrm policy add dir out src "$SOURCE/32" dst "$PEER/32" \
	tmpl src "$SOURCE" dst "$PEER" proto esp spi "$SPI" mode transport reqid "$REQID"

mark_dmesg
run_script --context=softirq "$SCRIPT"
ping -c 1 -W 1 -m "$OFFLOAD_MARK" -I "$IFACE" "$PEER" > /dev/null 2>&1
ping -c 1 -W 1 -m "$PLAIN_MARK" -I "$IFACE" "$OTHER" > /dev/null 2>&1
lunatik stop "$SCRIPT" 2>/dev/null

out=$(dmesg_since)
verdict offloaded "$OFFLOADED"
verdict plain "$PLAIN"
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

