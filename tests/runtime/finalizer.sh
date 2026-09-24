#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A script cannot run an object's __gc: the collector is its only caller.
#
# Every class metatable is its own __index, so the __gc it carries is reachable
# as a method, obj:__gc(), and through getmetatable(obj).__gc(obj). Either call
# drops the reference the userdata holds and, when that is the last one, runs the
# class release in whatever context the script is in. finalizer.lua calls __gc
# on a data object as a method, through the metatable, through pcall, and from the __gc of
# a table of its own, which the collector runs with its own steps stopped, and
# asserts the refusal on all four; then it drops an object under a debug line
# hook and grows a table, where the hook's own GC checkpoint is the only one
# and each step runs a whole cycle, so the collector calls the finalizer from
# the hooked frame; then it drops the object and collects, where the
# collector's own call is accepted, and leaves an object for the close to
# collect. None of the three leaves a __gc warning in the log, which a refused
# collector does.
#
# Usage: sudo bash tests/runtime/finalizer.sh

SCRIPT="tests/runtime/finalizer"
REFUSAL="not called as a finalizer"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

reported()
{
	dmesg_since | grep -cF "finalizer test: $1"
}

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$(reported "method $REFUSAL")" = 1 ] || fail "obj:__gc() was not refused"
[ "$(reported "metatable $REFUSAL")" = 1 ] || fail "getmetatable(obj).__gc(obj) was not refused"
[ "$(reported "pcall $REFUSAL")" = 1 ] || fail "pcall(obj.__gc, obj) was not refused"
ktap_pass "__gc called from a script is refused, as a method, through the metatable and through pcall"

[ "$(reported "sentinel $REFUSAL")" = 1 ] || fail "obj:__gc() from a finalizer of the script's own was not refused"
ktap_pass "__gc called from a finalizer the script wrote is refused"

[ "$(reported "hooked")" = 1 ] || fail "the script did not reach its hooked collection"
[ "$(reported "collected")" = 1 ] || fail "the script did not reach its collection"
[ "$(dmesg_since | grep -c "Lua warning")" = 0 ] || fail "a __gc raised a warning"
ktap_pass "the collector's call is accepted, from a step inside a debug hook, on a dropped object and at the close"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

