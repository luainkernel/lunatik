#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An object holds the module of its class from its creation to its release,
# and a state that a clone creates the metatables of a class in holds it until
# it closes.
#
# module_owner.lua requires set and leaves a set in lunatik._ENV. Once that
# runtime stops, its require no longer holds luaset, and the set is the only
# thing left that runs luaset's code: its release, when the entry goes. The
# refcnt of luaset is then one more than before the script ran, which keeps
# lunatik unload from removing luaset ahead of lunatik_run, whose exit drops
# _ENV and with it the set. module_owner_take.lua then takes the set out of
# _ENV twice, two clones in a runtime that never required set, clears the entry
# and collects. The set is gone, and the runtime still holds the metatables the
# first clone created there, whose methods are luaset's code, and the second
# found: while it runs, the refcnt is still one more, not two, and once it
# stops, back where it was.
#
# Without the references the set's release runs in freed memory once luaset is
# removed, so the test never removes a module: it reads the refcnt, and its
# cleanup takes the set out of _ENV before the suite unloads anything.
#
# Usage: sudo bash tests/runtime/module_owner.sh

SCRIPT="tests/runtime/module_owner"
TAKE="tests/runtime/module_owner_take"
MODULE="luaset"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik run "$TAKE" > /dev/null 2>&1
	lunatik stop "$TAKE" > /dev/null 2>&1
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

refcnt() { cat "/sys/module/$MODULE/refcnt" 2>/dev/null; }

trap cleanup EXIT
cleanup

before=$(refcnt) || skip_all "$MODULE not loaded"

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null 2>&1
[ "$(refcnt)" -eq $((before + 1)) ] ||
	fail "$MODULE refcnt $before -> $(refcnt) with a set left in _ENV by a stopped runtime, not one more"
ktap_pass "a set left in _ENV holds $MODULE after the runtime that created it stops"

run_script "$TAKE"
[ "$(refcnt)" -eq $((before + 1)) ] ||
	fail "$MODULE refcnt $before -> $(refcnt) while a runtime that took and dropped the set runs, not one more"
ktap_pass "a runtime that never required set holds $MODULE once for the metatables its two clones share"

lunatik stop "$TAKE" > /dev/null 2>&1
[ "$(refcnt)" -eq "$before" ] || fail "$MODULE refcnt $before -> $(refcnt) after the set was released and the runtime stopped"
ktap_pass "the set's release and the runtime's stop give $MODULE back"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

