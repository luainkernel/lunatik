#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Helpers the luaebpf cases share: the toolchain check that turns a missing tool into a skip,
# the compile into a scratch directory, the load into a pin root, and the differential run
# against the oracle a program file's own body wrote while it compiled.
# Source this file, and tests/lib.sh, from each case.

LUAEBPF_SRC=/lib/modules/lua/tests/luaebpf
LUAEBPF_PINS=/sys/fs/bpf/luaebpf
LUAEBPF_WORK=

cleanup() {
	rm -rf "$LUAEBPF_PINS"
	[ -n "$LUAEBPF_WORK" ] && rm -rf "$LUAEBPF_WORK"
	return 0
}

# why the case cannot run, or nothing at all
luaebpf_reason() {
	command -v lunatikc >/dev/null || { echo "lunatikc is not installed; run make install"; return; }
	command -v bpftool  >/dev/null || { echo "bpftool is not installed"; return; }
	mountpoint -q /sys/fs/bpf      || { echo "/sys/fs/bpf is not mounted"; return; }
	[ -r /sys/kernel/btf/vmlinux ] || { echo "the kernel publishes no BTF"; return; }
	[ -r "$LUAEBPF_SRC/pass.bpf.lua" ] || { echo "the program files are not installed"; return; }
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
		lunatikc bpf -o "$LUAEBPF_WORK/$name.bpf.o" "$LUAEBPF_SRC/$name.bpf.lua" ) 2>&1
}

luaebpf_loadall() {
	bpftool prog loadall "$LUAEBPF_WORK/$1.bpf.o" "$LUAEBPF_PINS" type xdp 2>&1
}

# the verifier's own log: the Lua line it quotes, the may_goto header before the kernel rewrites
# it into a loop counter, and the instruction budget each program cost
luaebpf_verbose() {
	bpftool -d prog loadall "$LUAEBPF_WORK/$1.bpf.o" "$LUAEBPF_PINS" type xdp 2>&1
}

luaebpf_verdict() {
	bpftool prog run pinned "$LUAEBPF_PINS/$1" data_in "$LUAEBPF_WORK/packet.bin" 2>&1 \
		| grep -oP 'Return value: \K[0-9]+'
}

# every row of the oracle against the program of the same name; where the interpreter raised,
# the compiled program owes the default verdict that row declared instead
luaebpf_differential() {
	local name value default got mismatch=0
	while IFS=$'\t' read -r name value default; do
		[ "$value" = "raises" ] && value="$default"
		got=$(luaebpf_verdict "$name")
		if [ "$got" != "$value" ]; then
			echo "$name: returned '$got', the interpreter says '$value'"
			mismatch=$((mismatch + 1))
		fi
	done < "$LUAEBPF_WORK/oracle.txt"
	[ "$mismatch" -eq 0 ]
}

# a refused construct: the message names the file and the line, the driver exits non-zero, and
# no object is left behind
luaebpf_refuses() {
	local name="$1" pattern="$2" out
	rm -f "$LUAEBPF_WORK/$name.bpf.o"
	out=$(cd "$LUAEBPF_WORK" && lunatikc bpf -o "$LUAEBPF_WORK/$name.bpf.o" \
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

