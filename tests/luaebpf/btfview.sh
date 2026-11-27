#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests bpf.vmlinux, which reads a kernel struct's layout out of the kernel's BTF,
# /sys/kernel/btf/vmlinux or the raw BTF file `lunatik bpf --btf` names. A program file's body asks
# it for five structs and writes what it answered beside the object; the case compares that with
# `bpftool btf dump file /sys/kernel/btf/vmlinux format raw`, the same BTF read by a different
# program.
#   - the size of xdp_md and of __sk_buff, and the byte offset of every field the context
#     proxies expose, match the dump's bits_offset divided by eight; the reader walks a flat
#     stream of variable-length records, so a mis-sized record shifts every offset after it
#   - each of those fields is four bytes, which is the only width the kernel lets a program use
#     on either context (net/core/filter.c's __is_valid_xdp_access and bpf_skb_is_valid_access)
#   - iphdr's whole-byte members are reported at the dump's offsets, while the dump's named
#     bitfields are no field of the layout and its anonymous union is absent from it
#   - every member reported of xdp_md, __sk_buff, iphdr, tcphdr and flowi_tunnel is marked bigendian
#     exactly where the dump types it __be16, __be32 or __be64, so iphdr's tot_len, tcphdr's seq and
#     flowi_tunnel's tun_id are, and iphdr's check, a __sum16, is not
#   - every bitfield the dump names of iphdr and tcphdr is reported, with a mask of its
#     bitfield_size bits under a naturally aligned load of 1, 2, 4 or 8 bytes that covers its bits
#   - views of the layouts of iphdr and tcphdr, over the SYN and the ClientHello of the corpus as
#     the compiler's packet twin reads them, read the version, ihl, total length, protocol,
#     destination port, doff and flags each packet carries, the TCP header found past the IPv4 one
#     by ihl: a shift a byte order gets wrong reads another nibble or flag
#   - a BTF the case writes, of a struct whose bitfields those of the kernel's own structs give no
#     instance of, answers through --btf: one of an int is reported signed, one that crosses the four
#     bytes of its type takes the load of eight that covers it, and one no load of eight bytes
#     covers is absent, though bpftool names it
#   - a struct the kernel does not publish raises a message naming it
#   - --btf on a copy of /sys/kernel/btf/vmlinux answers the same layouts, and the object is byte
#     for byte the one compiled without it
#   - the kernel's BTF swapped into the byte order the host does not use, which bpftool reads as it
#     reads the kernel's, answers the same layouts through --btf, a copy of the program file setting
#     luaebpf.emit.bigendian to that order, but for each bitfield's shift, which counts from the other
#     end of the same load, as BTF numbers a big-endian kernel's bits from the most significant
#   - a BTF of another byte order than the object's is refused naming both, the swapped one for an
#     object in the host's order and the running kernel's for one in the other, with no object left
#     behind
#   - --btf naming a file that cannot be read, one that holds no BTF header, an ELF object, and one
#     cut short of what its header sizes are refused naming the path
#
# Usage: sudo bash tests/luaebpf/btfview.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 16

DUMP=
LAYOUT=

host=$(host_order)
if [ "$host" = little ]; then other=big; else other=little; fi

# the byte offset bpftool reports for a member, or nothing when it is a bitfield
member() {
	awk -v want="'$1'" -v field="'$2'" '
		$2 == "STRUCT" && $3 == want { on = 1; next }
		on && $1 == field {
			for (i = 2; i <= NF; i++) {
				if ($i ~ /^bitfield_size=/) exit
				if ($i ~ /^bits_offset=/) { split($i, p, "="); bits = p[2] }
			}
			if (bits % 8 == 0) print bits / 8
			exit
		}
		on && $1 !~ /^'\''/ { exit }
	' "$DUMP"
}

# whether the dump lists the member at all, bitfield or anonymous union included
names() {
	awk -v want="'$1'" -v field="'$2'" '
		$2 == "STRUCT" && $3 == want { on = 1; next }
		on && $1 == field { found = 1; exit }
		on && $1 !~ /^'\''/ { exit }
		END { exit found ? 0 : 1 }
	' "$DUMP"
}

structsize() {
	awk -v want="'$1'" '
		$2 == "STRUCT" && $3 == want {
			for (i = 4; i <= NF; i++) if ($i ~ /^size=/) { split($i, p, "="); print p[2] }
			exit
		}
	' "$DUMP"
}

# the members the layout marks otherwise than the dump's typedef of them says: bigendian exactly for a
# __be16, a __be32 or a __be64
mismarked() {
	awk -v layout="$LAYOUT" '
		BEGIN {
			while ((getline line < layout) > 0) {
				split(line, f, "\t")
				if (f[1] == "field") { wanted["'\''" f[2] "'\''"] = 1; mark[f[2] "." f[3]] = f[6] }
			}
		}
		$2 == "TYPEDEF" { typedef[$1] = $3 }
		$1 ~ /^\[/ { on = ($2 == "STRUCT" && $3 in wanted) ? $3 : ""; next }
		on != "" {
			split($2, t, "=")
			member[substr(on, 2, length(on) - 2) "." substr($1, 2, length($1) - 2)] = "[" t[2] "]"
		}
		END {
			for (key in mark) {
				name = typedef[member[key]]
				want = name ~ /^'\''__be(16|32|64)'\''$/ ? "true" : "false"
				if (mark[key] != want) print key ": bigendian " mark[key] ", the dump types it " name
			}
		}
	' "$DUMP"
}

# the bitfields the dump names of a struct the layout reports bitfields of, that the layout reports
# otherwise than the dump's bits_offset and bitfield_size say: a mask of that many bits, under a
# naturally aligned load of 1, 2, 4 or 8 bytes that covers the bits
miscovered() {
	awk -v layout="$LAYOUT" '
		BEGIN {
			while ((getline line < layout) > 0) {
				split(line, f, "\t")
				if (f[1] == "bitfield") { wanted["'\''" f[2] "'\''"] = 1; load[f[2] "." f[3]] = f[4] " " f[5] " " f[6] }
			}
		}
		$1 ~ /^\[/ { on = ($2 == "STRUCT" && $3 in wanted) ? $3 : ""; next }
		on != "" && $4 ~ /^bitfield_size=/ {
			split($3, o, "="); split($4, b, "=")
			bits[substr(on, 2, length(on) - 2) "." substr($1, 2, length($1) - 2)] = o[2] " " b[2]
		}
		END {
			for (key in bits) {
				split(bits[key], m, " ")
				if (!(key in load)) { print key ": a bitfield the layout does not report"; continue }
				split(load[key], l, " ")
				aligned = (l[2] == 1 || l[2] == 2 || l[2] == 4 || l[2] == 8) && l[1] % l[2] == 0
				covers = l[1] * 8 <= m[1] && m[1] + m[2] <= (l[1] + l[2]) * 8
				if (!aligned || !covers || l[3] != 2 ^ m[2] - 1)
					print key ": a load at " l[1] " of " l[2] " bytes masked by " l[3] ", for " m[2] " bits at " m[1]
			}
		}
	' "$DUMP"
}

# the bitfields whose shift in the swapped BTF does not count from the other end of the load the
# kernel's own BTF shifts them in, the width of the load less the kernel's shift and the bitfield's
reversed() {
	awk -F'\t' '
		FILENAME == ARGV[1] { if ($1 == "bitfield") { size[$2 "." $3] = $5; mask[$2 "." $3] = $6 } next }
		FILENAME == ARGV[2] { native[$1 "." $2] = $3; next }
		{
			key = $1 "." $2; n++
			for (bits = 0; 2 ^ bits - 1 < mask[key]; bits++);
			if ($3 != size[key] * 8 - native[key] - bits)
				print key ": shift " $3 " in the swapped BTF, " native[key] " in the kernel'\''s"
		}
		END { if (n == 0) print "the swapped BTF answered no bitfield" }
	' "$LAYOUT" "$LUAEBPF_WORK/shift.txt" "$LUAEBPF_WORK/$other/shift.txt"
}

# crossing <out>: a raw little-endian BTF of the struct crossing, four bitfields of four-byte types:
# narrow, 4 bits of an unsigned int; negative, 4 of an int; wide, 20 that cross the unsigned int's
# four bytes; and uncovered, 30 that no eight naturally aligned bytes hold
crossing() {
	lua5.5 - "$1" <<'LUA'
local pack = string.pack

-- uapi/linux/btf.h: a btf_type's info holds its kind from bit 24 and a struct's kind_flag in bit 31, the
-- word after an INT its encoding from bit 24 and its bits, and a member's offset its bitfield size
-- from bit 24
local INT    <const> = 1 << 24
local STRUCT <const> = 1 << 31 | 4 << 24
local SIGNED <const> = 1 << 24
local BITS   <const> = 32

local strings = "\0unsigned int\0int\0crossing\0narrow\0negative\0wide\0uncovered\0"

local function name(text)
	return (strings:find("\0" .. text .. "\0", 1, true))
end

local function integer(text, encoding)
	return pack("<I4I4I4I4", name(text), INT, BITS // 8, encoding | BITS)
end

local function member(text, type, bit, bits)
	return pack("<I4I4I4", name(text), type, bits << 24 | bit)
end

local members = {member("narrow", 1, 0, 4), member("negative", 2, 4, 4), member("wide", 1, 20, 20),
	member("uncovered", 1, 40, 30)}
local types = integer("unsigned int", 0) .. integer("int", SIGNED) ..
	pack("<I4I4I4", name("crossing"), STRUCT | #members, 12) .. table.concat(members)
local file = assert(io.open(arg[1], "wb"))
assert(file:write(pack("<I2I1I1I4I4I4I4I4", 0xeb9f, 1, 0, 24, 0, #types, #types, #strings), types, strings))
assert(file:close())
LUA
}

# the byte offset and the width the reader answered for one field
reports() {
	awk -v what="$1" -v field="$2" '$1 == "field" && $2 == what && $3 == field {print $4, $5}' "$LAYOUT"
}

# every named field sits where the dump puts it, and the struct is the size the dump says
layout() {
	local what="$1" field want got width
	shift
	for field in "$@"; do
		want=$(member "$what" "$field")
		read -r got width <<<"$(reports "$what" "$field")"
		[ -n "$want" ] || { echo "$what.$field: the dump names no whole-byte member"; return 1; }
		[ "$got" = "$want" ] || { echo "$what.$field: offset '$got', the dump says '$want'"; return 1; }
	done
	want=$(structsize "$what")
	got=$(awk -v w="$what" '$1 == "size" && $2 == w {print $3}' "$LAYOUT")
	[ "$got" = "$want" ] || { echo "$what: size '$got', the dump says '$want'"; return 1; }
	return 0
}

XDP_FIELDS="ingress_ifindex rx_queue_index data data_end"
SKB_FIELDS="len hash ifindex ingress_ifindex priority data data_end"

output=$(luaebpf_compile btfview) || { comment "$output"; fail "luaebpf: btfview.bpf.lua did not compile"; }
DUMP="$LUAEBPF_WORK/btf.txt"
LAYOUT="$LUAEBPF_WORK/layout.txt"
bpftool btf dump file /sys/kernel/btf/vmlinux format raw > "$DUMP" \
	|| fail "luaebpf: the kernel BTF could not be dumped"

output=$(layout xdp_md $XDP_FIELDS) && output=$(layout __sk_buff $SKB_FIELDS)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: a context field is not where the kernel BTF puts it"; }
ktap_pass "luaebpf: every context field the proxies expose sits where bpftool reports"

for field in $XDP_FIELDS; do
	read -r _ width <<<"$(reports xdp_md "$field")"
	[ "$width" = 4 ] || fail "luaebpf: xdp_md.$field is $width bytes, and XDP takes only four"
done
for field in $SKB_FIELDS; do
	read -r _ width <<<"$(reports __sk_buff "$field")"
	[ "$width" = 4 ] || fail "luaebpf: __sk_buff.$field is $width bytes, and a tc program takes only four"
done
ktap_pass "luaebpf: every context field the proxies expose is four bytes"

output=$(layout iphdr tos tot_len id frag_off ttl protocol)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: an iphdr member is not where the kernel BTF puts it"; }
for absent in ihl version "(anon)"; do
	names iphdr "$absent" || fail "luaebpf: the dump names no iphdr member '$absent' to exclude"
	[ -z "$(reports iphdr "$absent")" ] \
		|| fail "luaebpf: the layout reports iphdr.$absent, which is no whole-byte integer"
done
ktap_pass "luaebpf: a bitfield is no field, an anonymous union is absent, and the whole-byte members are fields"

output=$(mismarked)
[ -z "$output" ] && grep -q "^field	iphdr	tot_len	.*	true$" "$LAYOUT" \
	|| { comment "$output"; fail "luaebpf: a member is marked bigendian otherwise than the dump types it"; }
ktap_pass "luaebpf: a member is marked bigendian exactly where the dump types it a big-endian typedef"

output=$(miscovered)
[ -z "$output" ] && grep -q "^bitfield	tcphdr	doff	" "$LAYOUT" \
	|| { comment "$output"; fail "luaebpf: a bitfield is not reported under a load that covers its bits"; }
ktap_pass "luaebpf: every bitfield is reported with its mask, under an aligned load that covers its bits"

views=$'syn 4 5 44 6 443 6 1 0 0\ntls 4 5 112 6 443 5 0 1 1'
[ "$(cat "$LUAEBPF_WORK/view.txt")" = "$views" ] \
	|| { comment "$(cat "$LUAEBPF_WORK/view.txt")"; fail "luaebpf: a view of iphdr and tcphdr misreads a packet"; }
ktap_pass "luaebpf: views of iphdr and tcphdr read each packet's version, ihl, ports, doff and flags by name"

crossing "$LUAEBPF_WORK/crossing.btf" \
	&& bpftool btf dump file "$LUAEBPF_WORK/crossing.btf" format raw | grep -q "'uncovered' .*bitfield_size=30" \
	|| fail "luaebpf: the BTF of a struct of crossing bitfields could not be written"
cp "$LUAEBPF_SRC/crossing.bpf.lua" "$LUAEBPF_WORK/"
output=$(luaebpf_written crossing --btf="$LUAEBPF_WORK/crossing.btf" 2>&1) \
	|| { comment "$output"; fail "luaebpf: crossing.bpf.lua did not compile over the BTF the case wrote"; }
crossed=$'narrow 0 4 false 0 15\nnegative 0 4 true 4 15\nwide 0 8 false 20 1048575'
[ "$(cat "$LUAEBPF_WORK/crossing.txt")" = "$crossed" ] \
	|| { comment "$(cat "$LUAEBPF_WORK/crossing.txt")"; fail "luaebpf: a bitfield past its type's bytes is not under the load that covers it"; }
ktap_pass "luaebpf: a bitfield past its type's bytes takes the wider load, a signed one is signed, one no load covers is absent"

grep -q "^missing	false	the kernel BTF has no struct 'a_struct_no_kernel_publishes'$" "$LAYOUT" \
	|| { comment "$(grep '^missing' "$LAYOUT")"; fail "luaebpf: an unpublished struct does not raise with its name"; }
ktap_pass "luaebpf: a struct the kernel does not publish raises a message naming it"

cp /sys/kernel/btf/vmlinux "$LUAEBPF_WORK/vmlinux.btf" && mkdir -p "$LUAEBPF_WORK/copy" \
	|| fail "luaebpf: the kernel BTF could not be copied"
output=$(cd "$LUAEBPF_WORK/copy" && lunatik bpf --btf="$LUAEBPF_WORK/vmlinux.btf" \
	-o "$LUAEBPF_WORK/copy/btfview.bpf.o" "$LUAEBPF_SRC/btfview.bpf.lua" 2>&1) \
	|| { comment "$output"; fail "luaebpf: btfview.bpf.lua did not compile through --btf"; }
cmp -s "$LUAEBPF_WORK/copy/layout.txt" "$LAYOUT" \
	|| { comment "$(diff "$LAYOUT" "$LUAEBPF_WORK/copy/layout.txt")"; fail "luaebpf: --btf on a copy answers other layouts"; }
cmp -s "$LUAEBPF_WORK/copy/btfview.bpf.o" "$LUAEBPF_WORK/btfview.bpf.o" \
	|| fail "luaebpf: --btf on a copy writes another object"
ktap_pass "luaebpf: --btf on a copy of the kernel BTF answers the same layouts and writes the same object"

luaebpf_swapped /sys/kernel/btf/vmlinux "$LUAEBPF_WORK/swapped.btf" \
	|| fail "luaebpf: the kernel BTF could not be swapped into the $other-endian order"
bpftool btf dump file "$LUAEBPF_WORK/swapped.btf" format raw | cmp -s - "$DUMP" \
	|| fail "luaebpf: bpftool does not read the swapped BTF as the kernel's"
output=$(luaebpf_ordered $other btfview --btf="$LUAEBPF_WORK/swapped.btf") \
	|| { comment "$output"; fail "luaebpf: btfview.bpf.lua did not compile $other-endian through the swapped BTF"; }
cmp -s "$LUAEBPF_WORK/$other/layout.txt" "$LAYOUT" \
	|| { comment "$(diff "$LAYOUT" "$LUAEBPF_WORK/$other/layout.txt")"; fail "luaebpf: the swapped BTF answers other layouts"; }
ktap_pass "luaebpf: the kernel BTF swapped into the order the host does not use answers the same layouts"

output=$(reversed)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: a bitfield's shift does not count from the swapped end"; }
ktap_pass "luaebpf: a bitfield's shift in the swapped BTF counts from the other end of the same load"

cp "$LUAEBPF_SRC/btfview.bpf.lua" "$LUAEBPF_WORK/" || fail "luaebpf: btfview.bpf.lua could not be copied"
output=$(luaebpf_refuses btfview "$LUAEBPF_WORK/swapped.btf is a $other-endian BTF, for a $host-endian object" \
	--btf="$LUAEBPF_WORK/swapped.btf") \
	|| { comment "$output"; fail "luaebpf: a $other-endian BTF is not refused for a $host-endian object"; }
ktap_pass "luaebpf: a BTF in the order the host does not use is refused naming both for an object in the host's"

rm -f "$LUAEBPF_WORK/$other/btfview.bpf.o"
output=$(luaebpf_ordered $other btfview)
[ $? -ne 0 ] && grep -qF "/sys/kernel/btf/vmlinux is a $host-endian BTF, for a $other-endian object" <<< "$output" \
	&& [ ! -e "$LUAEBPF_WORK/$other/btfview.bpf.o" ] \
	|| { comment "$output"; fail "luaebpf: the kernel BTF is not refused for a $other-endian object"; }
ktap_pass "luaebpf: the running kernel's BTF is refused naming both for an object in the order the host does not use"

output=$(luaebpf_refuses btfview "$LUAEBPF_WORK/missing.btf: No such file or directory" \
	--btf="$LUAEBPF_WORK/missing.btf") || { comment "$output"; fail "luaebpf: a BTF that cannot be read is not refused"; }
ktap_pass "luaebpf: --btf naming a file that cannot be read is refused naming it"

output=$(luaebpf_refuses btfview "$LUAEBPF_WORK/copy/btfview.bpf.o carries no BTF header" \
	--btf="$LUAEBPF_WORK/copy/btfview.bpf.o") || { comment "$output"; fail "luaebpf: a file with no BTF header is not refused"; }
ktap_pass "luaebpf: --btf naming a file with no BTF header, an ELF object, is refused naming it"

head -c 1000 /sys/kernel/btf/vmlinux > "$LUAEBPF_WORK/cut.btf" || fail "luaebpf: the kernel BTF could not be cut"
output=$(luaebpf_refuses btfview "$LUAEBPF_WORK/cut.btf is shorter than its BTF header says" \
	--btf="$LUAEBPF_WORK/cut.btf") || { comment "$output"; fail "luaebpf: a BTF cut short is not refused"; }
ktap_pass "luaebpf: --btf naming a BTF cut short of what its header sizes is refused naming it"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

