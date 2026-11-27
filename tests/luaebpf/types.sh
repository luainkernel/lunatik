#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the declaration of a type by a lowering, without a program: the CLI's Lua loads
# `luaebpf.emit.frame` alone and declares types through `frame.type`, which the frame's checks
# read through the classes a declaration joins.
#   - a type declared into `word` and `untested` takes a bit of its own, under its name, in those
#     two classes and not in `proxy`, and one declared into no class sits in none
#   - a class the frame does not read is refused at the declaring line, naming the class
#
# Usage: sudo bash tests/luaebpf/types.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

CASES=2

cleanup() {
	return 0
}
trap cleanup EXIT

ktap_header
ktap_plan $CASES

lua5.5 "$DIR/searchpath.host.lua" luaebpf.emit.frame 2>/dev/null \
	|| skip_script "luaebpf: luaebpf is not installed; run make and make install"

mark_dmesg

output=$(lua5.5 "$DIR/declared.host.lua" 2>&1) \
	|| { comment "$output"; fail "luaebpf: a declared type does not take its bit, its name and its classes"; }
ktap_pass "luaebpf: a declared type takes a bit of its own, its name and the classes it names, and no other"

output=$(lua5.5 "$DIR/bogusclass.host.lua" 2>&1)
status=$?
[ $status -ne 0 ] && grep -qF "bogusclass.host.lua:8: 'bogus' is not a class the frame reads" <<< "$output" \
	|| { comment "$output"; fail "luaebpf: a type declared into a class the frame does not read is not refused at its line"; }
ktap_pass "luaebpf: a type declared into a class the frame does not read is refused at the declaring line, naming the class"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

