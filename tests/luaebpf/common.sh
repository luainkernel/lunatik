#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Helpers the luaebpf cases share: the toolchain check that turns a missing tool into a skip,
# and the run of a program file's body in a scratch directory.
# Source this file, and tests/lib.sh, from each case.

# the program files install beside the cases, out of the tree the kernel's require reads
LUAEBPF_SRC=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
LUAEBPF_SCRIPTS=/lib/modules/lua/tests/luaebpf
LUAEBPF_KERNELCHUNK=$LUAEBPF_SCRIPTS/kernelchunk.lua
LUAEBPF_WORK=

cleanup() {
	rm -f "$LUAEBPF_KERNELCHUNK"
	[ -n "$LUAEBPF_WORK" ] && rm -rf "$LUAEBPF_WORK"
	return 0
}

# why the case cannot run, or nothing at all
luaebpf_reason() {
	command -v lunatic  >/dev/null || { echo "lunatic is not installed; run make and make install"; return; }
}

# the plan, the skips a missing tool turns every case into, and a scratch directory of its own
luaebpf_start() {
	local reason i
	ktap_header
	ktap_plan "$1"
	reason=$(luaebpf_reason)
	if [ -n "$reason" ]; then
		for i in $(seq "$1"); do ktap_skip "luaebpf: $reason"; done
		ktap_totals
		exit 0
	fi
	cleanup
	LUAEBPF_WORK=$(mktemp -d)
	mark_dmesg
}

# lunatic compiles an installed program file, and the CLI's Lua runs its body from that chunk in
# the scratch directory
luaebpf_compile() {
	( cd "$LUAEBPF_WORK" && lua5.5 - "$LUAEBPF_SRC/$1.bpf.lua" ) 2>&1 <<'LUA'
local proto = require("luaebpf.proto")
proto.load(arg[1])()
LUA
}

