#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# rcu.foreach() leaves no reference held when its handle's protected call overflows
# the stack before the callback is reached.
#
# The walk takes a reference on an entry's object and hands it to the clone the
# callback receives; the reference is taken inside the handle's lua_pcall, so a
# pcall that overflows the 200-slot Lua stack (lunatik_conf.h) before the handle
# runs takes none to leave held. foreach_overflow.lua stores one data object in a
# one-bucket table, then walks it from a function carrying a swept count of stack
# slots, 0 up to past where the call itself overflows, so the walk's own entry fits
# at some counts while the handle's pcall does not; it does this for a fresh table
# and object each count, then drops every table and collects. A kprobe on
# luadata_release counts the objects freed: every object stored is released, since
# the script keeps no handle on it and the walk left none. Kprobes on luarcu_lforeach
# and luarcu_foreach_handle count the walks entered and the handles run, and a walk
# entered whose handle never ran is one whose pcall overflowed in that window: at
# least one does, or the case did not reach the path under test. A build that takes
# the reference before the pcall leaves one held for each such walk, and those
# objects are never freed.
#
# Usage: sudo bash tests/rcu/foreach_overflow.sh

SCRIPT="tests/rcu/foreach_overflow"
FREED="lunatik_rcu_overflow/luadata_release"
WALKS="lunatik_rcu_overflow/luarcu_lforeach"
HANDLES="lunatik_rcu_overflow/luarcu_foreach_handle"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	kprobe_remove "$FREED"
	kprobe_remove "$WALKS"
	kprobe_remove "$HANDLES"
}

trap cleanup EXIT
cleanup

kprobe_place "$FREED" luadata_release || skip_all "couldn't place a kprobe on luadata_release"
kprobe_place "$WALKS" luarcu_lforeach || skip_all "couldn't place a kprobe on luarcu_lforeach"
kprobe_place "$HANDLES" luarcu_foreach_handle || skip_all "couldn't place a kprobe on luarcu_foreach_handle"

ktap_header
ktap_plan 3

mark_dmesg
before=$(kprobe_hits "$FREED")
walks=$(kprobe_hits "$WALKS")
handles=$(kprobe_hits "$HANDLES")
run_script "$SCRIPT"
freed=$(( $(kprobe_hits "$FREED") - before ))
overflowed=$(( $(kprobe_hits "$WALKS") - walks - ($(kprobe_hits "$HANDLES") - handles) ))
lunatik stop "$SCRIPT" > /dev/null 2>&1

objects=$(dmesg_since | grep -o "foreach_overflow: [0-9]* objects" | tail -1 | awk '{print $2}')
[ -n "$objects" ] || fail "the script did not report how many objects it stored"

if [ "$freed" -eq "$objects" ]; then
	ktap_pass "every object a walk read is released, with none left held by an overflowed walk"
else
	ktap_fail "$freed of the $objects objects released: an overflowed walk left $(( objects - freed )) held"
fi

if [ "$overflowed" -gt 0 ]; then
	ktap_pass "$overflowed walks overflowed between their own entry and their handle's, the path under test"
else
	ktap_fail "no walk overflowed between its own entry and its handle's: the path under test was not reached"
fi

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

