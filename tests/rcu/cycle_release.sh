#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Two rcu.tables stored in each other are released once their handles go, and a store
# from a kprobe walks and releases as one from a script's body does.
#
# An entry holds a reference on the object it stores, and a reference count does not
# see a cycle: two tables each stored in the other would keep each other alive after
# every handle is gone. cycle_release.lua stores b in a, tries to store a in b, which
# the walk refuses, drops both handles and collects them; a kprobe on luarcu_release
# counts the tables released while the script runs, which is both of them. A build
# that accepts the second store releases neither.
#
# cycle_hook.lua, in a hardirq runtime, makes the same stores from a kprobe on the
# personality syscall, which one setarch calls once: the walk's lock is taken there
# with interrupts off, the store that would close the cycle is refused and the one
# after the edge is deleted is taken, and deleting the entry that held a table's last
# reference releases it in the handler, where the release waits on the same lock.
#
# Usage: sudo bash tests/rcu/cycle_release.sh

SCRIPT="tests/rcu/cycle_release"
HOOK="tests/rcu/cycle_hook"
RELEASED="lunatik_rcu_cycle/luarcu_release"
TABLES=2 # the pair cycle_release.lua drops

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$HOOK" > /dev/null 2>&1
	kprobe_remove "$RELEASED"
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

trap cleanup EXIT
cleanup

command -v setarch > /dev/null 2>&1 || skip_all "setarch not available"
kprobe_place "$RELEASED" luarcu_release || skip_all "couldn't place a kprobe on luarcu_release"

ktap_header
ktap_plan 4

mark_dmesg
before=$(kprobe_hits "$RELEASED")
run_script "$SCRIPT"
released=$(( $(kprobe_hits "$RELEASED") - before ))
lunatik stop "$SCRIPT" > /dev/null 2>&1

if [ "$released" -eq "$TABLES" ]; then
	ktap_pass "two tables a refused store kept apart are released when their handles go"
else
	ktap_fail "$released of the $TABLES tables released after their handles went: a cycle kept them"
fi

before=$(kprobe_hits "$RELEASED")
run_script --context=hardirq "$HOOK"
setarch "$(uname -m)" -R true > /dev/null 2>&1
sleep 1
released=$(( $(kprobe_hits "$RELEASED") - before ))
lunatik stop "$HOOK" > /dev/null 2>&1

hooked() { dmesg_since | grep -qF "rcu cycle_hook: $1"; }
if ! hooked refused; then
	ktap_fail "a kprobe handler's store that closes a cycle was not refused with ELOOP"
elif ! hooked stored; then
	ktap_fail "a kprobe handler's store into a table it no longer reaches did not return"
else
	ktap_pass "a store from a kprobe refuses a cycle and takes a table that closes none"
fi

if [ "$released" -eq 1 ]; then
	ktap_pass "a table whose last reference an entry held is released in the kprobe handler"
else
	ktap_fail "$released tables released by the handler, not the one its entry held"
fi

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

