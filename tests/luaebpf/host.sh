#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the compiler host: lunatic compiling a program file, and the CLI's Lua running the body
# from that chunk, rewritten in its own numbering.
#   - the body computes as the kernel does: 10 / 4 is the integer 2, and "10" // 3 is 3, which
#     takes the metamethod event the rewrite renumbers; it requires bpf.xdp, linux.xdp.action
#     and luaebpf.proto, class from the kernel scripts rather than the compiler's lunatik.class,
#     and a module installed as the stripped chunk lunatic writes, whose own 10 / 4 is 2
#   - the body's require reads none of the host's modules: class and struct come from the kernel
#     scripts though a Lua module on LUA_PATH_5_5 and a C one on LUA_CPATH_5_5 carry their names,
#     and a luaebpf.* module the compiler itself does not load is reached through the host's path
#   - luaebpf.proto.read hands back a function's own bytecode: its numparams, maxstacksize, first
#     opcode, first line and source are asserted in the body, and a '/' reads as IDIV
#   - a function and the one it returns, and two functions, written on one line, each read as
#     themselves
#   - xdp.program, which the CLI's Lua compiled from source, is refused as a compiled function
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

# modules the host installs, named as kernel scripts; the C one is an empty file, which the C
# searcher would hand to dlopen ahead of the kernel scripts
shadow="$LUAEBPF_WORK/shadow"
mkdir "$shadow"
echo 'return function() end' > "$shadow/class.lua"
: > "$shadow/struct.so"

# a luaebpf.* module only the host's path carries
mkdir "$shadow/luaebpf"
echo 'return "host"' > "$shadow/luaebpf/probe.lua"

# the versioned names are what lua5.5 reads first, whatever the environment exports
output=$(LUA_PATH_5_5="$shadow/?.lua;;" LUA_CPATH_5_5="$shadow/?.so;;" luaebpf_compile host)
if [ $? -ne 0 ]; then
	comment "$output"
	fail "luaebpf: the body does not run lunatic's bytecode, reads a host module, or hands over other bytecode"
fi
ktap_pass "luaebpf: the body runs lunatic's bytecode, reads no host module, and hands over that bytecode"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

