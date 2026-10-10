#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A monitored method's raise names the method.
#
# lunatik_monitor calls the method under lua_pcall from C, where luaL_argerror finds no
# name for it and writes '?', and rewrites the '?' of the raise into the name the wrapper
# carries. name.lua calls a fifo's pop past the capacity and reads the raise whole:
# "bad argument #2 to 'pop' (out of bounds)".
#
# Usage: sudo bash tests/monitor/name.sh

SCRIPT="tests/monitor/name"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

# passed <case>: tests.lib reports PASS and the name of each case that passed
passed() { dmesg_since | grep -qE "PASS[[:space:]]$1\$"; }

ktap_header
ktap_plan 2

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null

case="a monitored method's raise names the method"
passed "$case" || fail "$case: $(dmesg_since | grep -F "$case")"
ktap_pass "$case"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

