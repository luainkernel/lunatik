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

lua5.5 -e 'assert(package.searchpath("luaebpf.emit.frame", package.path))' 2>/dev/null \
	|| { for i in $(seq $CASES); do ktap_skip "luaebpf: luaebpf is not installed; run make and make install"; done; ktap_totals; exit 0; }

mark_dmesg

output=$(lua5.5 - 2>&1 <<'LUA'
local frame = require("luaebpf.emit.frame")
local classes, typenames = frame.classes, frame.typenames
local A = frame.type("a", "word", "untested")
local B = frame.type("b")
assert(A ~= B and A & B == 0, "two types share a bit")
assert(typenames[A] == "a" and typenames[B] == "b", "a type is not recorded under its name")
assert(classes.word & A ~= 0 and classes.untested & A ~= 0, "a type is missing from a class it declared")
assert(classes.proxy & A == 0, "a type joined a class it did not declare")
assert((classes.word | classes.proxy | classes.untested) & B == 0, "a type declared into no class joined one")
LUA
) || { comment "$output"; fail "luaebpf: a declared type does not take its bit, its name and its classes"; }
ktap_pass "luaebpf: a declared type takes a bit of its own, its name and the classes it names, and no other"

output=$(lua5.5 - 2>&1 <<'LUA'
local frame = require("luaebpf.emit.frame")
frame.type("x", "bogus")
LUA
)
status=$?
[ $status -ne 0 ] && grep -qF "stdin:2: 'bogus' is not a class the frame reads" <<< "$output" \
	|| { comment "$output"; fail "luaebpf: a type declared into a class the frame does not read is not refused at its line"; }
ktap_pass "luaebpf: a type declared into a class the frame does not read is refused at the declaring line, naming the class"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

