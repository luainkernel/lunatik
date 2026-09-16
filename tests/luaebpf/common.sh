#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Helpers the luaebpf cases share: the toolchain check that turns a missing tool into a skip,
# the kfunc check that does the same for a case calling into a runtime, the compile into a
# scratch directory, the load into a pin root, the differential run against the oracle a program
# file's own body wrote while it compiled, and, for the loader cases, the device they attach to
# and what a failed `lunatik run` may not leave behind.
# Source this file, and tests/lib.sh, from each case.

LUAEBPF_SRC=/lib/modules/lua/tests/luaebpf
LUAEBPF_PINS=/sys/fs/bpf/luaebpf
LUAEBPF_MAPS=/sys/fs/bpf/luaebpf/maps
LUAEBPF_DEPLOY=/sys/fs/bpf/lunatik
LUAEBPF_ROOT=$LUAEBPF_DEPLOY/tests/luaebpf
LUAEBPF_DEV=luaebpf0
LUAEBPF_PEER=luaebpf1
LUAEBPF_WORK=
# the example cases deploy the tree's own examples, each on a veth pair of its own
LUAEBPF_FILTER=examples/filter/sni
LUAEBPF_FILTERDEV=filter0
LUAEBPF_FILTERPEER=filter1
LUAEBPF_CLASSIFY=examples/sniclassify/sni
LUAEBPF_CLASSIFYDEV=classify0
LUAEBPF_CLASSIFYPEER=classify1

# whatever a loader case left running, and only that: `lunatik stop` probes the modules, and
# every case in the suite runs this cleanup twice
luaebpf_stopall() {
	local script
	for script in $(lunatik list 2>/dev/null | tr ',' ' '); do
		case "$script" in
		tests/luaebpf/*|./tests/luaebpf/*) lunatik stop "$script" > /dev/null 2>&1 ;;
		esac
	done
}

cleanup() {
	luaebpf_stopall
	lunatik stop "$LUAEBPF_FILTER" > /dev/null 2>&1
	lunatik stop "$LUAEBPF_CLASSIFY" > /dev/null 2>&1
	rm -rf "$LUAEBPF_PINS" "$LUAEBPF_ROOT" "$LUAEBPF_DEPLOY/$LUAEBPF_FILTER" \
		"$LUAEBPF_DEPLOY/$LUAEBPF_CLASSIFY"
	rm -f "$LUAEBPF_SRC"/*.bpf.o
	ip link del "$LUAEBPF_DEV" 2>/dev/null
	ip link del "$LUAEBPF_FILTERDEV" 2>/dev/null
	ip link del "$LUAEBPF_CLASSIFYDEV" 2>/dev/null
	[ -n "$LUAEBPF_WORK" ] && rm -rf "$LUAEBPF_WORK"
	return 0
}

# why the case cannot run, or nothing at all
luaebpf_reason() {
	command -v lunatikc >/dev/null || { echo "lunatikc is not installed; run make install"; return; }
	command -v bpftool  >/dev/null || { echo "bpftool is not installed"; return; }
	command -v ip       >/dev/null || { echo "ip is not installed"; return; }
	mountpoint -q /sys/fs/bpf      || { echo "/sys/fs/bpf is not mounted"; return; }
	[ -r /sys/kernel/btf/vmlinux ] || { echo "the kernel publishes no BTF"; return; }
	[ -r "$LUAEBPF_SRC/pass.bpf.lua" ] || { echo "the program files are not installed"; return; }
	lua5.4 -e 'require("lunatik.loader")' 2>/dev/null \
		|| { echo "lunatik.loader is not installed; run make install"; return; }
}

# why a case that loads a program calling into a runtime cannot run: the module publishes the
# kfunc only from v6.4 on (lib/luaxdp.c), and a kernel below it publishes the BTF without it
luaebpf_kfunc() {
	local module="$1" name="$2"
	[ -r "/sys/kernel/btf/$module" ] || { echo "$module publishes no BTF"; return; }
	bpftool btf dump file "/sys/kernel/btf/$module" format raw 2>/dev/null \
		| grep -q "FUNC '$name'" || echo "$module publishes no $name"
}

# the whole plan skipped for one reason: the plan is printed before a case knows whether the
# kernel offers what it exercises, and a kernel that does not owes a skip rather than a failure
luaebpf_skipall() {
	local i
	for i in $(seq "$1"); do ktap_skip "luaebpf: $2"; done
	ktap_totals
	exit 0
}

# the plan, the skips a missing tool turns every case into, and a scratch directory of its own
luaebpf_start() {
	local reason
	ktap_header
	ktap_plan "$1"
	reason=$(luaebpf_reason)
	[ -n "$reason" ] && luaebpf_skipall "$1" "$reason"
	cleanup
	LUAEBPF_WORK=$(mktemp -d)
	mkdir -p "$LUAEBPF_PINS"
	# BPF_PROG_TEST_RUN on XDP refuses anything shorter than an ethernet header
	printf '\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00' > "$LUAEBPF_WORK/packet.bin"
	mark_dmesg
}

# compiles an installed program file; the body runs here, so its oracle lands in the scratch
# directory beside the object. The probe override is passed only where a row names one, since an
# empty allow-list would be one that offers the compiler nothing.
luaebpf_compile() {
	local name="$1"
	( cd "$LUAEBPF_WORK" && env LUAEBPF_DROP="${2:-}" ${3:+LUAEBPF_PROBE=$3} \
		lunatikc bpf -o "$LUAEBPF_WORK/$name.bpf.o" "$LUAEBPF_SRC/$name.bpf.lua" ) 2>&1
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

# a refused construct: the message names the file and the line, the driver exits non-zero, and
# no object is left behind
luaebpf_refuses() {
	local name="$1" pattern="$2" out
	rm -f "$LUAEBPF_WORK/$name.bpf.o"
	out=$(cd "$LUAEBPF_WORK" && env ${3:+LUAEBPF_PROBE=$3} lunatikc bpf -o "$LUAEBPF_WORK/$name.bpf.o" \
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

# `make install` compiles every program file it installs except the ones here, so a loader case
# stages its own object where `lunatik run` looks for it, beside the installed script
luaebpf_install() {
	local name="$1"
	( cd "$LUAEBPF_WORK" && LUAEBPF_DROP="${2:-}" \
		lunatikc bpf -o "$LUAEBPF_SRC/$name.bpf.o" "$LUAEBPF_SRC/$name.bpf.lua" ) 2>&1
}

# a veth pair of the suite's own, so a loader case never races tests/xdp on lunatik0; an example
# case names a pair of its own, since it deploys on the device a loader case is already using
luaebpf_device() {
	local dev="${1:-$LUAEBPF_DEV}" peer="${2:-$LUAEBPF_PEER}"
	ip link add "$dev" type veth peer name "$peer" 2>&1 || return 1
	ip link set "$dev" up
	ip link set "$peer" up
}

# what a run of <script> may not leave behind when it fails, on the device it attached to
luaebpf_residue() {
	local script="$1" dev="${2:-$LUAEBPF_DEV}" left=
	[ -d "$LUAEBPF_DEPLOY/$script" ] && left="$left a pin root"
	lunatik list | grep -q "$script" && left="$left a runtime"
	# a tcx program sits under `tc:`, so this is the device's own entry and not a fixed line
	bpftool net show dev "$dev" | grep -q "^$dev(" && left="$left a program on $dev"
	echo "$left"
}

# one row of a refused run: it exits non-zero with the message the row names and undoes every
# step it took. The teardown runs before the checks, so a failing row leaves the next one a
# clean device.
luaebpf_undone() {
	local title="$1" name="$2" pattern="$3" output status left
	shift 3
	output=$(lunatik run "tests/luaebpf/$name" "$@" 2>&1)
	status=$?
	left=$(luaebpf_residue "tests/luaebpf/$name")
	lunatik stop "tests/luaebpf/$name" > /dev/null 2>&1
	rm -rf "${LUAEBPF_ROOT:?}/$name"
	if [ -z "$output" ]; then
		comment "the run printed nothing"
	elif [ "$status" -eq 0 ]; then
		comment "the run exited 0"
	elif ! echo "$output" | grep -qE "$pattern"; then
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

