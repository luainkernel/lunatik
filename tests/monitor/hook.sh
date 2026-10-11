#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A debug hook runs no script under a monitored object's lock.
#
# lunatik_monitor calls a method under lua_pcall holding the object's lock, spin_lock_bh for a
# fifo, where a call or return hook would fire at the method's own call and return and run the
# script's hook function in an atomic section its process runtime does not know it is in. The
# monitor clears such a hook for the method and restores it after; a line or count hook, which
# a method written in C never fires, stays set. hook.lua, a process runtime, sets a call hook, a
# return hook and one of each, pushes and pops a fifo, and reads what each hook saw of the C
# functions it called: push and pop, the wrappers, and never the method the monitor calls under
# the lock. A call and return hook set across a pop past the capacity, which raises, sees the
# push after it: the monitor restores the hook on a raise too. A count hook of 100 instructions
# set over 1000 pushes and pops, which run fewer instructions apart than that, fires, which a
# count hook cleared and restored at every call, its countdown restarted each time, never does.
# Last, it sets a call and return hook that sleeps with linux.schedule on every event, once a
# hook that does not sleep has read the events from outside the lock, so a build that runs the
# hook under the lock fails there instead of sleeping under the spinlock. The kernel log then
# holds no "BUG: scheduling while atomic", which __schedule_bug prints for a sleep with bottom
# halves off and which the pattern check_dmesg reads does not match.
#
# Usage: sudo bash tests/monitor/hook.sh

SCRIPT="tests/monitor/hook"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

# passed <case>: tests.lib reports PASS and the name of each case that passed
passed() { dmesg_since | grep -qE "PASS[[:space:]]$1\$"; }

ktap_header
ktap_plan 6

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null

for case in \
	"a call or return hook sees a monitored method's call and return and not the method's own" \
	"a call or return hook stays set after a monitored method raises" \
	"a count hook keeps counting across monitored methods" \
	"a hook that sleeps on every event runs outside a monitored method's lock"; do
	passed "$case" || fail "$case: $(dmesg_since | grep -F "$case")"
	ktap_pass "$case"
done

sched=$(dmesg_since | grep "BUG: scheduling while atomic" || true)
[ -n "$sched" ] && fail "a hook slept under a monitored method's lock: $sched"
ktap_pass "no hook slept under a monitored method's lock"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

