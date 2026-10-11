#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A monitored method's raise names the method, leaves the rest of its message whole and
# reaches the caller as raised when it is not a string.
#
# lunatik_monitor calls the method under lua_pcall from C, where luaL_argerror finds no
# name for it and writes "to '?'", and rewrites that text into the name the wrapper
# carries. name.lua calls a fifo's pop past the capacity and reads the raise whole:
# "bad argument #2 to 'pop' (out of bounds)". It then resumes a runtime of name_raise.lua,
# whose body raises "ready?", and reads the raise of resume, a monitored method, whole:
# "ready?" and the newline resume appends, its "?" left as the body wrote it. Last, it
# sets a call hook that raises on the method's call, inside the monitor's protected call,
# and reads back what pop raised: a number, then a table, each as the hook raised it. The
# number comes first: a build that rewrites any raise converts it into a string and the
# case fails there, before the table, which that build reads as a NULL string.
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
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null

for case in \
	"a monitored method's raise names the method" \
	"a resumed runtime's message reaches the caller of resume whole" \
	"a monitored method's raise that is not a string reaches the caller as raised"; do
	passed "$case" || fail "$case: $(dmesg_since | grep -F "$case")"
	ktap_pass "$case"
done

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

