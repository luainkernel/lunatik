#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the compiler host: lunatic compiling a program file, and the CLI's Lua running the body
# from that chunk, rewritten in its own numbering.
#   - the body computes as the kernel does: 10 / 4 is the integer 2, and "10" // 3 is 3, which
#     takes the metamethod event the rewrite renumbers; it requires linux.xdp.action
#     and luaebpf.proto, class from the kernel scripts rather than the compiler's lunatik.class,
#     and a module installed as the stripped chunk lunatic writes, whose own 10 / 4 is 2
#   - luaebpf.proto.read hands back a function's own bytecode: its numparams, maxstacksize, first
#     opcode, first line and source are asserted in the body, and a '/' reads as IDIV
#   - a function and the one it returns, and two functions, written on one line, each read as
#     themselves
# The body asserts and raises, so the case reads what the CLI's Lua printed and its exit status.
#
# Usage: sudo bash tests/luaebpf/host.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 1

# BYTECODE=1 installs a module as the stripped chunk lunatic writes
echo 'return {width = 10 / 4}' > "$LUAEBPF_WORK/kernelchunk.lua"
lunatic -s -o "$LUAEBPF_KERNELCHUNK" "$LUAEBPF_WORK/kernelchunk.lua" || fail "luaebpf: lunatic wrote no chunk"

output=$(luaebpf_compile host)
if [ $? -ne 0 ]; then
	comment "$output"
	fail "luaebpf: the body does not run lunatic's bytecode, or its functions are not that bytecode"
fi
ktap_pass "luaebpf: the body runs lunatic's bytecode, and the functions it hands over are that bytecode"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

