#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A runtime, and a percpu set, closes when the collector takes its last handle.
#
# collected_child.lua requires byteorder, which holds the module until the
# child's state closes, so its refcnt reads how many children are open. The
# child run on its own raises it by one and gives it back at its stop, which is
# what the next read relies on. collected.lua then creates a runtime and a
# percpu set of that child, keeps neither handle and collects: when its body
# returns, the refcnt is back where it was, before the driver itself stops.
#
# Usage: sudo bash tests/runtime/collected.sh

SCRIPT="tests/runtime/collected"
CHILD="tests/runtime/collected_child"
MODULE="luabyteorder"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHILD" > /dev/null 2>&1
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

refcnt() { cat "/sys/module/$MODULE/refcnt" 2>/dev/null; }

trap cleanup EXIT
cleanup

before=$(refcnt) || skip_all "$MODULE not loaded"

ktap_header
ktap_plan 3

mark_dmesg
run_script "$CHILD"
[ "$(refcnt)" -eq $((before + 1)) ] || fail "$MODULE refcnt $before -> $(refcnt) while the child runs, not one more"
lunatik stop "$CHILD" > /dev/null 2>&1
[ "$(refcnt)" -eq "$before" ] || fail "$MODULE refcnt $before -> $(refcnt) after the child stopped"
ktap_pass "the child holds $MODULE from its require to its stop"

run_script "$SCRIPT"
[ "$(refcnt)" -eq "$before" ] ||
	fail "$MODULE refcnt $before -> $(refcnt) after the driver collected its children: one per runtime left open"
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "a runtime and a percpu set whose last handles are collected close"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

