#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for GC-under-spinlock in lunatik_monitor (PR #459).
# A spawned thread uses a sleep=false fifo from a sleep=true runtime.
# lunatik_monitor holds spin_lock_bh for fifo methods; f:pop() allocates
# a long Lua string inside the monitor, triggering GC that finalizes a
# dropped AF_PACKET socket. Without the fix (lua_gc stop/restart around
# the spinlock), mutex_lock sleeps under spin_lock_bh and the kernel
# panics with "BUG: scheduling while atomic".
#
# Usage: sudo bash tests/monitor/gc.sh

SCRIPT="tests/monitor/gc"
SLEEP=1

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
mark_ts=$(awk '{print $1}' /proc/uptime)

lunatik spawn "$SCRIPT"
sleep $SLEEP
lunatik stop "$SCRIPT"

check_dmesg || exit 1
# scan dmesg since mark_ts for "scheduling while atomic" (GC-under-spinlock panic)
sched=$(dmesg | awk -v ts="$mark_ts" \
	'match($0, /\[[ ]*([0-9]+\.[0-9]+)/, a) && a[1]+0 >= ts+0' | \
	grep "scheduling while atomic" || true)
[ -n "$sched" ] && fail "GC ran under spinlock: scheduling while atomic"
ktap_pass "GC did not run under spinlock"

ktap_totals

