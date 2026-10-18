#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# set.fromdata refuses a data that views memory it does not own: a netfilter hook on LOCAL_OUT,
# reached by a ping to the loopback address, passes its skb:data() to set.fromdata, which raises
# "external memory" and builds nothing over a packet its callback no longer holds once it
# returns.
#
# Usage: sudo bash tests/set/view.sh

SCRIPT="tests/set/view"
MARK=1915 # MARK in view.lua

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
run_script --context=softirq "$SCRIPT"
ping -c 1 -W 1 -m "$MARK" 127.0.0.1 > /dev/null 2>&1
lunatik stop "$SCRIPT" 2>/dev/null

out=$(dmesg_since)
check_dmesg || { ktap_totals; exit 1; }
failed=$(echo "$out" | grep -o "set view: FAIL.*" | head -1)
if [ -n "$failed" ]; then
	ktap_fail "set/view: $failed"
elif echo "$out" | grep -q "set view: ok"; then
	ktap_pass "set/view: set.fromdata refuses a data that views a packet"
else
	ktap_fail "set/view: the hook never ran"
fi

ktap_totals

