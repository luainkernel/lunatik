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
# class release in whatever context the script is in, past the registry pin that
# keeps a registered object for lua_close. finalizer.lua calls __gc both ways on a
# data object and asserts the refusal, then drops the object and collects, where
# the collector's own call is accepted, and the script's close collects the rest:
# neither leaves a __gc warning in the log, which a release run twice does.
#
# Usage: sudo bash tests/runtime/finalizer.sh

SCRIPT="tests/runtime/finalizer"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

reported()
{
	dmesg_since | grep -cF "finalizer test: $1"
}

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT"

[ "$(reported "method not allowed outside a finalizer")" = 1 ] || fail "obj:__gc() was not refused"
[ "$(reported "metatable not allowed outside a finalizer")" = 1 ] || fail "getmetatable(obj).__gc(obj) was not refused"
ktap_pass "__gc called from a script is refused, as a method and through the metatable"

[ "$(reported "collected")" = 1 ] || fail "the collector's own call did not run"
[ "$(dmesg_since | grep -c "error in __gc")" = 0 ] || fail "a __gc raised a warning"
ktap_pass "the collector's call is accepted, and the close collects what is left"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

