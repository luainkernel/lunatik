#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Helpers the luaebpf cases share: the toolchain check that turns a missing tool into a skip, the
# module BTF check that does the same for a case calling the kernel Lua runtime, the compile into a
# scratch directory, in either byte order, the kernel's BTF swapped into the other, the load into a
# pin root, the differential run against the oracle a program file's own body wrote while it
# compiled, and, for the loader cases, the device they attach to and what a refused `lunatik run`
# may not leave behind.
# Source this file, and tests/lib.sh, from each case.

# the program files install beside the cases, out of the tree the kernel's require reads
LUAEBPF_SRC=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
LUAEBPF_SCRIPTS=/lib/modules/lua/tests/luaebpf
LUAEBPF_PINS=/sys/fs/bpf/luaebpf
LUAEBPF_KERNELCHUNK=$LUAEBPF_SCRIPTS/kernelchunk.lua
LUAEBPF_MAPS=/sys/fs/bpf/luaebpf/maps
LUAEBPF_ROOT=/sys/fs/bpf/lunatik/tests/luaebpf
LUAEBPF_DEV=luaebpf0
LUAEBPF_PEER=luaebpf1
LUAEBPF_WORK=
# the scripts a loader case runs, which the cleanup stops; set before luaebpf_start
LUAEBPF_RUNS=

cleanup() {
	local name
	for name in $LUAEBPF_RUNS; do
		lunatik stop "tests/luaebpf/$name" > /dev/null 2>&1
	done
	rm -rf "$LUAEBPF_PINS" "$LUAEBPF_ROOT"
	rm -f "$LUAEBPF_KERNELCHUNK" "$LUAEBPF_SCRIPTS"/*.bpf.o
	ip link del "$LUAEBPF_DEV" 2>/dev/null
	[ -n "$LUAEBPF_WORK" ] && rm -rf "$LUAEBPF_WORK"
	return 0
}

# why the case cannot run, or nothing at all
luaebpf_reason() {
	command -v lunatic  >/dev/null || { echo "lunatic is not installed; run make and make install"; return; }
	command -v bpftool  >/dev/null || { echo "bpftool is not installed"; return; }
	mountpoint -q /sys/fs/bpf      || { echo "/sys/fs/bpf is not mounted"; return; }
	[ -r /sys/kernel/btf/vmlinux ] || { echo "the kernel publishes no BTF"; return; }
	[ -r "$LUAEBPF_SRC/pass.bpf.lua" ] || { echo "the program files are not installed"; return; }
}

# why a case cannot load a program calling the kernel Lua runtime through <module>'s kfunc, which
# libbpf resolves in the module's BTF, or nothing at all
luaebpf_kfunc() {
	[ -r "/sys/kernel/btf/$1" ] || echo "$1 publishes no BTF; run make btf_install, then make install"
}

# whether the running kernel takes the may_goto header a loop without a proven bound needs
luaebpf_maygoto() {
	[ "$(printf '%s\n6.9\n' "$(uname -r | cut -d. -f1,2)" | sort -V | head -1)" = "6.9" ]
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
	mkdir -p "$LUAEBPF_PINS"
	# BPF_PROG_TEST_RUN on XDP refuses anything shorter than an ethernet header
	printf '\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00' > "$LUAEBPF_WORK/packet.bin"
	mark_dmesg
}

# compiles an installed program file; the body runs here, so its oracle lands in the scratch
# directory beside the object
luaebpf_compile() {
	local name="$1"
	( cd "$LUAEBPF_WORK" && LUAEBPF_DROP="${2:-}" \
		lunatik bpf -o "$LUAEBPF_WORK/$name.bpf.o" "$LUAEBPF_SRC/$name.bpf.lua" ) 2>&1
}

# no type argument: the section a program's entry sits in is what libbpf reads its type from.
# The map directory is made here rather than once, since a case may clear the pin root between
# two loads of its own.
luaebpf_loadall() {
	mkdir -p "$LUAEBPF_MAPS"
	bpftool prog loadall "$LUAEBPF_WORK/$1.bpf.o" "$LUAEBPF_PINS" pinmaps "$LUAEBPF_MAPS" 2>&1
}

# the verifier's own log: the Lua line it quotes, the may_goto header before the kernel rewrites
# it into a loop counter, and the instruction budget each program cost
luaebpf_verbose() {
	mkdir -p "$LUAEBPF_MAPS"
	bpftool -d prog loadall "$LUAEBPF_WORK/$1.bpf.o" "$LUAEBPF_PINS" pinmaps "$LUAEBPF_MAPS" 2>&1
}

# one program over the packet and the context the row named, or over the fourteen bytes
# BPF_PROG_TEST_RUN demands of an XDP program where a row named none
luaebpf_verdict() {
	local name="$1" context="${2:-}" out="${3:-}" data="$LUAEBPF_WORK/packet.bin" args=()
	if [ -n "$context" ]; then
		data="$LUAEBPF_WORK/$context.bin"
		args=(ctx_in "$LUAEBPF_WORK/$context.ctx")
		[ -n "$out" ] && args+=(ctx_out "$out")
	fi
	bpftool prog run pinned "$LUAEBPF_PINS/$name" data_in "$data" "${args[@]}" 2>&1 \
		| grep -oP 'Return value: \K[0-9]+'
}

# every row of the oracle against the program of the same name; where the interpreter raised,
# the compiled program owes the default verdict that row declared instead
luaebpf_differential() {
	local name value default context got mismatch=0
	while IFS=$'\t' read -r name value default context; do
		[ "$value" = "raises" ] && value="$default"
		got=$(luaebpf_verdict "$name" "$context")
		if [ "$got" != "$value" ]; then
			echo "$name: returned '$got', the interpreter says '$value'"
			mismatch=$((mismatch + 1))
		fi
	done < "$LUAEBPF_WORK/oracle.txt"
	[ "$mismatch" -eq 0 ]
}

# luaebpf_refuses <name> <pattern> [<option>...]: a refused construct, the program file compiled with
# the options given: the message names the file and the line, the CLI exits non-zero, and no object
# is left behind
luaebpf_refuses() {
	local name="$1" pattern="$2" out
	shift 2
	rm -f "$LUAEBPF_WORK/$name.bpf.o"
	out=$(cd "$LUAEBPF_WORK" && lunatik bpf "$@" -o "$LUAEBPF_WORK/$name.bpf.o" \
		"$LUAEBPF_WORK/$name.bpf.lua" 2>&1)
	if [ $? -eq 0 ]; then
		echo "$name: compiled, and the construct should have been refused"
		return 1
	fi
	if ! echo "$out" | grep -qF "$pattern"; then
		echo "$name: expected '$pattern', got: $out"
		return 1
	fi
	if [ -e "$LUAEBPF_WORK/$name.bpf.o" ]; then
		echo "$name: an object was written for a refused program"
		return 1
	fi
	return 0
}

# luaebpf_ordered <order> <name> [<option>...]: the program file <name> compiled, with the options
# given, from a copy whose first line sets luaebpf.emit.bigendian to <order>, little or big, in a
# directory of that order's own, so the copy carries the name the object takes
luaebpf_ordered() {
	local order="$1" name="$2" dir="$LUAEBPF_WORK/$1" bigendian=false
	shift 2
	[ "$order" = big ] && bigendian=true
	mkdir -p "$dir"
	{
		echo "require(\"luaebpf.emit\").bigendian = $bigendian"
		cat "$LUAEBPF_SRC/$name.bpf.lua"
	} > "$dir/$name.bpf.lua"
	( cd "$dir" && lunatik bpf "$@" -o "$dir/$name.bpf.o" "$dir/$name.bpf.lua" ) 2>&1
}

# luaebpf_swapped <btf> <out>: the raw BTF <btf> written to <out> in the other byte order. Past the
# magic, the version and the flags, every field of the header and of the types is a word, as
# libbpf's btf_bswap_hdr and btf_bswap_type_rest swap them, and the strings are bytes
luaebpf_swapped() {
	lua5.5 - "$1" "$2" <<'LUA'
local pack, unpack = string.pack, string.unpack
local insert       = table.insert

local MAGIC <const> = 0xeb9f
local WORD  <const> = 4

local file = assert(io.open(arg[1], "rb"))
local bytes = file:read("a")
file:close()

local from = unpack("<I2", bytes) == MAGIC and "<" or ">"
local to = from == "<" and ">" or "<"
local hdrlen, typeoff, typelen = unpack(from .. "I4I4I4", bytes, 5)
local types = hdrlen + typeoff
local out = {pack(to .. "I2", MAGIC), bytes:sub(3, 4)}

local function swap(first, last)
	for at = first, last, WORD do
		insert(out, pack(to .. "I4", (unpack(from .. "I4", bytes, at))))
	end
end

swap(5, hdrlen)
insert(out, bytes:sub(hdrlen + 1, types))
swap(types + 1, types + typelen)
insert(out, bytes:sub(types + typelen + 1))
file = assert(io.open(arg[2], "wb"))
assert(file:write(table.concat(out)))
assert(file:close())
LUA
}

# `make install` compiles no program file of this suite, so a loader case puts its own object
# where `lunatik run` looks for it, beside the installed script
luaebpf_stage() {
	luaebpf_compile "$@" && cp "$LUAEBPF_WORK/$1.bpf.o" "$LUAEBPF_SCRIPTS/"
}

# a veth pair of the suite's own, so a loader case never races tests/xdp on lunatik0
luaebpf_device() {
	ip link add "$LUAEBPF_DEV" type veth peer name "$LUAEBPF_PEER" || return 1
	ip link set "$LUAEBPF_DEV" up && ip link set "$LUAEBPF_PEER" up
}

# the id of the XDP program a device carries, $LUAEBPF_DEV unless one is named, or nothing
luaebpf_attached() {
	bpftool net show dev "${1:-$LUAEBPF_DEV}" | grep -oP 'driver id \K[0-9]+'
}

# what a refused run may not leave behind
luaebpf_residue() {
	local left=
	[ -d "$LUAEBPF_ROOT/$1" ] && left="$left a pin root"
	lunatik list | grep -qxF "tests/luaebpf/$1" && left="$left a runtime"
	[ -n "$(luaebpf_attached)" ] && left="$left a program on $LUAEBPF_DEV"
	echo "$left"
}

# luaebpf_undone <title> <name> <status> <pattern> [<option>...]: the run of tests/luaebpf/<name>
# exits <status> with a message matching <pattern> and leaves nothing behind. The teardown runs
# before the checks, so a failing row leaves the next one a clean device.
luaebpf_undone() {
	local title="$1" name="$2" expected="$3" pattern="$4" output status left
	shift 4
	output=$(lunatik run "$@" "tests/luaebpf/$name" 2>&1)
	status=$?
	left=$(luaebpf_residue "$name")
	lunatik stop "tests/luaebpf/$name" > /dev/null 2>&1
	if [ "$status" -ne "$expected" ]; then
		comment "the run exited $status, not $expected"
	elif ! grep -qE "$pattern" <<< "$output"; then
		comment "the message does not match '$pattern'"
	elif [ -n "$left" ]; then
		comment "the run left$left"
	else
		ktap_pass "luaebpf: $title"
		return 0
	fi
	comment "$output"
	ktap_fail "luaebpf: $title"
	return 1
}

