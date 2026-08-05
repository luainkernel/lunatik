#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for percpu netfilter affinity: a hook registered by a percpu
# instance only acts on packets processed on its instance's CPU and accepts
# everything else. Each instance counts the LOCAL_OUT packets to 127.0.0.9 it
# handled; after K pings the counts must add up to exactly K -- without the
# affinity every packet would fire all N hooks and the sum would be N*K.
#
# Usage: sudo bash tests/runtime/percpu_affinity.sh

SCRIPT="tests/runtime/percpu_affinity"
CHECK="tests/runtime/percpu_affinity_check"
PACKETS=7  # must match percpu_affinity_check.lua

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHECK" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

cat /sys/module/luanetfilter/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: luanetfilter not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

run_script "$SCRIPT" softirq percpu

ping -c $PACKETS -i 0.1 -W 1 127.0.0.9 > /dev/null 2>&1 || true

run_script "$CHECK"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "each packet is handled by exactly one percpu instance"

ktap_totals

