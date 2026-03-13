#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Verifies that skb and skb:data() are SINGLE objects that cannot be stored
# in _ENV. Registers a LOCAL_OUT netfilter hook, triggers it via loopback
# ping, and asserts that both _ENV assignments fail with "cannot share
# SINGLE object".
#
# Usage: sudo bash tests/runtime/opt_skb_single.sh

SCRIPT="tests/runtime/opt_skb_single"
MODULE="luanetfilter"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

lunatik run "$SCRIPT" false
ping -c 1 -W 1 127.0.0.1 > /dev/null 2>&1 || true

check_dmesg || { ktap_totals; exit 1; }
ktap_pass "skb and skb:data() correctly rejected as SINGLE from _ENV"

ktap_totals

