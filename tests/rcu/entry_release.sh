#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The value an rcu.table entry drops is released after the table's lock.
#
# Every rcu.table is a SOFTIRQ class object, so a write holds its spinlock, and
# the value of the entry a write replaces or removes is put when the entry
# goes: when that reference was the object's last, its release runs on the
# writing task, a runtime's lua_close and every release of its state among the
# ones that can sleep. entry_release.lua stores two children, each requiring
# byteorder, as the only reference their entries hold, then removes one entry
# and replaces the other from its body: each child closes there, and the
# module's use count is back where it was when the body returns. Where each
# close ran, under the lock or after it, a kprobe on lunatik_releaseobject
# says: a hit taken with bottom halves off carries `b` in its flags, `D` where
# the handler also runs with interrupts masked, as arm64's does, and neither
# with them on, on any kernel. The children hold nothing that sleeps on close,
# so a build that puts under the lock fails the read and not the host.
#
# Usage: sudo bash tests/rcu/entry_release.sh

SCRIPT="tests/rcu/entry_release"
MODULE="luabyteorder"
TRACING="/sys/kernel/tracing"
INSTANCE="$TRACING/instances/lunatik_rcu"
RELEASES="lunatik_rcu/lunatik_releaseobject"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	if [ -d "$INSTANCE" ]; then
		echo 0 > "$INSTANCE/events/$RELEASES/enable" 2>/dev/null
		rmdir "$INSTANCE"
	fi
	grep -q ":$RELEASES " "$TRACING/kprobe_events" 2>/dev/null && echo "-:$RELEASES" >> "$TRACING/kprobe_events"
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

refcnt() { cat "/sys/module/$MODULE/refcnt" 2>/dev/null; }
# the first flag of each hit the writing task took: `b` or `D` with bottom halves off
flags() { awk '$1 ~ /^lunatik-/ && $5 == "lunatik_releaseobject:" { print substr($3, 1, 1) }' "$INSTANCE/trace"; }

trap cleanup EXIT
cleanup

before=$(refcnt) || skip_all "$MODULE not loaded"
echo "p:$RELEASES lunatik_releaseobject" >> "$TRACING/kprobe_events" 2>/dev/null || skip_all "no kprobe events in tracefs"
mkdir "$INSTANCE" && echo 1 > "$INSTANCE/events/$RELEASES/enable" || skip_all "couldn't enable the kprobe on lunatik_releaseobject"

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"
[ "$(refcnt)" -eq "$before" ] ||
	fail "$MODULE refcnt $before -> $(refcnt) after the entries dropped their children: one left open"
ktap_pass "a child whose only reference is a table entry closes when the entry is removed or replaced"

hits=$(flags | wc -l)
[ "$hits" -ge 2 ] || fail "lunatik_releaseobject hit $hits times on the writing task, fewer than the two children"
off=$(flags | grep -c '^[bD]$')
[ "$off" -eq 0 ] || fail "$off of $hits releases ran with bottom halves off: under the table's lock"
ktap_pass "each child was released with bottom halves on, after the table's lock"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

