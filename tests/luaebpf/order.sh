#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the byte order the compiler writes an object in, the one luaebpf.emit.bigendian names:
# the kernel's that lunatik.config carries, or the one a program file's body sets it to. The
# program files of call and mapget are copied into the scratch directory under a first line that
# sets the order, once to the host's and once to the other, and each copy is compiled.
#   - readelf reads each object in the order its body set
#   - llvm-objdump disassembles each object of the other order, for that order's target, to the
#     instructions and relocations it reads in the host order's object for the host's: call's
#     subprograms and the relocations of their calls, mapget's maps and the relocations of their
#     lookups; skipped where llvm-objdump is not installed
#   - bpftool reads the same BTF out of both orders, the maps' DATASEC among it
#   - a map spec is read in the object's order: with the body set to the other order, a key in the
#     host's explicit order is refused with its line, and with the body set to either order, a key in
#     that order's explicit prefix, one in "=" and one with no order compile
#
# Usage: sudo bash tests/luaebpf/order.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 6

PROGRAMS="call mapget"

host=$(host_order)
if [ "$host" = little ]; then other=big; else other=little; fi
declare -A bigendian=([little]=false [big]=true) prefix=([little]='<' [big]='>') triple=([little]=bpfel [big]=bpfeb)

# disassembly <order> <name>: what llvm-objdump reads in <name>'s object of that order, for that
# order's target, without the raw bytes and the file name
disassembly() {
	llvm-objdump --triple="${triple[$1]}" -d -r --no-show-raw-insn "$LUAEBPF_WORK/$1/$2.bpf.o" | tail -n +3
}

# keyed <name> <order> <spec>: a program file whose body sets <order> and declares a map keyed by <spec>
keyed() {
	{
		echo "require(\"luaebpf.emit\").bigendian = ${bigendian[$2]}"
		echo 'local map = require("bpf.map")'
		echo 'local xdp = require("bpf.xdp")'
		echo "local keyed = map.hash(\"keyed\", {key = \"$3\", value = \"I4\", entries = 4})"
		echo 'return xdp.program(function(_) return 0 end)'
	} > "$LUAEBPF_WORK/$1.bpf.lua"
}

for name in $PROGRAMS; do
	for order in $host $other; do
		output=$(luaebpf_ordered $order $name) \
			|| { comment "$output"; fail "luaebpf: $name.bpf.lua did not compile $order-endian"; }
	done
done
ktap_pass "luaebpf: a body that sets luaebpf.emit.bigendian compiles in either order"

for name in $PROGRAMS; do
	for order in $host $other; do
		header=$(readelf -h "$LUAEBPF_WORK/$order/$name.bpf.o")
		grep -q "Data:.*$order endian" <<< "$header" \
			|| { comment "$header"; fail "luaebpf: readelf does not read $name.bpf.o as $order-endian"; }
	done
done
ktap_pass "luaebpf: readelf reads each object in the order its body set"

if ! command -v llvm-objdump >/dev/null; then
	ktap_skip "luaebpf: llvm-objdump is not installed"
else
	for name in $PROGRAMS; do
		native=$(disassembly $host $name)
		crossed=$(disassembly $other $name)
		[ -n "$native" ] && [ "$crossed" = "$native" ] \
			|| { comment "$(diff <(echo "$native") <(echo "$crossed"))"; fail "luaebpf: llvm-objdump reads $name's orders apart"; }
	done
	ktap_pass "luaebpf: llvm-objdump reads the other order's objects as the host order's, relocations included"
fi

for name in $PROGRAMS; do
	native=$(bpftool btf dump file "$LUAEBPF_WORK/$host/$name.bpf.o" 2>&1)
	crossed=$(bpftool btf dump file "$LUAEBPF_WORK/$other/$name.bpf.o" 2>&1)
	[ -n "$native" ] && [ "$crossed" = "$native" ] \
		|| { comment "$(diff <(echo "$native") <(echo "$crossed"))"; fail "luaebpf: bpftool reads $name's BTF apart"; }
done
bpftool btf dump file "$LUAEBPF_WORK/$other/mapget.bpf.o" | grep -q "DATASEC '.maps'" \
	|| fail "luaebpf: mapget's $other-endian BTF carries no .maps"
ktap_pass "luaebpf: bpftool reads the same BTF out of either order"

keyed hostkey $other "${prefix[$host]}I4"
output=$(luaebpf_refuses hostkey "hostkey.bpf.lua:4: a map is read in the kernel's byte order, not '${prefix[$host]}I4'") \
	|| { comment "$output"; fail "luaebpf: a key in the host's order is not refused for a $other-endian object"; }
ktap_pass "luaebpf: a key in the host's explicit order is refused for an object of the other"

for order in $host $other; do
	for spec in "${prefix[$order]}I4" "=I4" "I4"; do
		keyed ownkey $order "$spec"
		output=$(cd "$LUAEBPF_WORK" && lunatik bpf -o "$LUAEBPF_WORK/ownkey.bpf.o" "$LUAEBPF_WORK/ownkey.bpf.lua" 2>&1) \
			|| { comment "$output"; fail "luaebpf: a key '$spec' does not compile for a $order-endian object"; }
	done
done
ktap_pass "luaebpf: a key in the object's explicit order, in '=' and in none compiles, in either order"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

