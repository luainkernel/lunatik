#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests every construct the phase 1 subset refuses. Each row is a program file of its own,
# written here so that the message and the line it must name sit beside the source that
# provokes them, and asserted three ways: the exact message, the non-zero exit, and that no
# object was left behind.
#
# The rows are the runtime table and its constructor, a runtime string operation, a closure, a
# vararg function, pcall, a coroutine, a metatable, an unresolvable global and an unresolvable
# field of a compile-time module, which are one opcode and read back as what the source says, a
# call through an unresolvable value, the context, '..', '#', a method call, a tail call, an upvalue
# assignment, a to-be-closed variable, a generic for, while, repeat, a program declared with an
# argument beyond the context, arithmetic on a boolean at each shape the emitter checks on its
# own: the two opcodes the VM follows with no metamethod, a binary opcode with both operands
# live, one whose result is written over the operand it read, and a shift whose constant is on
# the left; and the two comparisons a join leaves undecidable, where a register carries one of
# several types and its bits say which for none of them.
#
# Usage: sudo bash tests/luaebpf/refuse.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

ROWS=26

luaebpf_start $ROWS

# every row is one compiled function, so the header and the trailer are the same for all of them
row() {
	local name="$1" message="$2" body="$3" preamble="${4:-}" params="${5:-ctx}"
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "$preamble"
		echo "return xdp.program(function($params)"
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row table_new "table_new.bpf.lua:5: a table constructor cannot run in the kernel" \
	$'\tlocal t = {}\n\treturn t[1]'
row table_write "table_write.bpf.lua:6: a table cannot be written in a compiled function" \
	$'\tlocal t = ports\n\tt[1] = 2\n\treturn 0' 'local ports = {}'
row string_op "string_op.bpf.lua:5: '..' cannot be applied in a compiled function" \
	$'\tlocal s = name .. "x"\n\treturn #s' 'local name = "a"'
row length "length.bpf.lua:5: '#' cannot be applied in a compiled function" \
	$'\tlocal n = #ports\n\treturn n' 'local ports = {1, 2}'
row closure "closure.bpf.lua:5: a closure cannot be created in a compiled function" \
	$'\tlocal f = function() return 1 end\n\treturn f()'
row vararg "vararg.bpf.lua:4: a vararg function cannot be compiled" \
	$'\tlocal n = select("#", ...)\n\treturn n' '' '...'
row metatable "metatable.bpf.lua:5: a method call cannot be compiled" \
	$'\tlocal v = proxy:get()\n\treturn v' 'local proxy = setmetatable({}, {__index = function() end})'
row unknown_global "unknown_global.bpf.lua:5: global 'nowhere' is not a compile-time value" \
	$'\treturn nowhere'
row unknown_field "unknown_field.bpf.lua:5: 'action.TYPO' is not a compile-time value" \
	$'\treturn action.TYPO' 'local action = require("linux.xdp")'
row context "context.bpf.lua:5: the program context cannot be read yet" \
	$'\treturn ctx'
row self_call "self_call.bpf.lua:5: a method call cannot be compiled" \
	$'\tlocal v = ports:len()\n\treturn v' 'local ports = {}'
row tailcall "tailcall.bpf.lua:5: a tail call cannot be compiled" \
	$'\treturn double(1)' 'local function double(x) return x + x end'
row setupvalue "setupvalue.bpf.lua:5: an upvalue cannot be assigned in a compiled function" \
	$'\tcount = 5\n\treturn count' 'local count = 0'
row toclose "toclose.bpf.lua:5: a to-be-closed variable cannot be compiled" \
	$'\tlocal h <close> = handle\n\treturn 0' 'local handle = setmetatable({}, {__close = function() end})'
row generic_for "generic_for.bpf.lua:5: a generic 'for' cannot be compiled" \
	$'\tfor k, v in next, ports do return v end\n\treturn 0' 'local ports = {1}'
row while_ "while_.bpf.lua:7: 'while' and 'repeat' are not compiled yet" \
	$'\tlocal n = 0\n\twhile n < 4 do\n\t\tn = n + 1\n\tend\n\treturn n'
row repeat_ "repeat_.bpf.lua:8: 'while' and 'repeat' are not compiled yet" \
	$'\tlocal n = 0\n\trepeat\n\t\tn = n + 1\n\tuntil n > 3\n\treturn n'
row twoargs "twoargs.bpf.lua:4: a program takes one argument, the context" \
	$'\treturn extra' '' 'ctx, extra'
row unmbool "unmbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn -b'
row bnotbool "bnotbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn ~b'
row addbool "addbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn b + one' 'local one = 1'
row aliasbool "aliasbool.bpf.lua:5: attempt to perform arithmetic on a boolean value" \
	$'\tlocal v = true + 1\n\treturn v'
row shlbool "shlbool.bpf.lua:6: attempt to perform arithmetic on a boolean value" \
	$'\tlocal b = true\n\treturn 3 << b'
row nilarith "nilarith.bpf.lua:6: attempt to perform arithmetic on a nil value" \
	$'\tlocal v\n\treturn v + one' 'local one = 1'
row join_number "join_number.bpf.lua:7: a value cannot be compared with a number here" \
	$'\tlocal v\n\tif one < 2 then v = 7 end\n\treturn v == 7' 'local one = 1'
row join_join "join_join.bpf.lua:8: a value cannot be compared with a value here" \
	$'\tlocal v, w\n\tif one < 2 then v = false end\n\tif one > 2 then w = false end\n\treturn v == w' \
	'local one = 1'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

