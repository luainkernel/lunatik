#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the packet proxy: ctx:packet() and the reads the kernel's own data object publishes.
#   - every accessor of lib/luadata.c -- getbyte, getuint8, getint8, getuint16, getint16,
#     getuint32, getint32, getint64 and getnumber -- over every packet of the corpus, against
#     the interpreted twin reading the same bytes with string.unpack. A wrong width, offset or
#     sign extension changes the number; the offset is the source address, whose first byte has
#     its high bit set, so the signed rows have something to extend
#   - '#' on the packet, which is the distance between the context's two bounds and must equal
#     the bytes prog run was handed
#   - an accessor at an offset an earlier read computed, so the bound on a computed offset is
#     exercised and not only the folded constant one
#   - an accessor asked for two results, where Lua fills the second with nil: a second result
#     left carrying the receiver's type answers the read instead of the fill
#   - an accessor inside a called function: examples/common/sni.lua's u16 helper, unchanged. The
#     proxy passes in one argument, and a failed bounds check there reaches the program's
#     default verdict through the flag a callee raises in its caller's frame
#   - a method neither proxy publishes is refused by name. getuint64 is the one a reader expects
#     and the kernel object does not have: a Lua integer is 64-bit signed, with no unsigned twin
#   - an accessor called without an offset, or with one that is not a number, is refused. The
#     first row throws a read away before it, so the argument register is left holding that
#     read's offset: without the check the call reads there rather than refusing
#
# Usage: sudo bash tests/luaebpf/packet.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 6

output=$(luaebpf_compile packet) || { comment "$output"; fail "luaebpf: packet.bpf.lua did not compile"; }
output=$(luaebpf_loadall packet) || { comment "$output"; fail "luaebpf: the packet reads did not verify"; }
ktap_pass "luaebpf: every packet row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a packet read differs"; }
ktap_pass "luaebpf: every packet read answers what the interpreter reads off the same bytes"

# every row is one compiled function over the context, so only the body differs
row() {
	local name="$1" line="$2" message="$3" body="$4"
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo 'return xdp.program(function(ctx)'
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:$line: $message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row nomethod 5 "the packet has no method 'getuint64'" \
	$'\tlocal p = ctx:packet()\n\tlocal v = p:getuint64(0)\n\treturn v'
row noctxmethod 5 "the context has no method 'bytes'" \
	$'\tlocal p = ctx:packet()\n\tlocal v = ctx:bytes()\n\treturn v'
row nooffset 6 "'getbyte' takes an offset" \
	$'\tlocal p = ctx:packet()\n\tp:getbyte(3)\n\tlocal v = p:getbyte()\n\treturn v'
row booleanat 5 "'getuint16' takes a number, not a boolean" \
	$'\tlocal p = ctx:packet()\n\tlocal v = p:getuint16(true)\n\treturn v'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

