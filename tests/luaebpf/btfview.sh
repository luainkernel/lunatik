#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests luaebpf.vmlinux, which reads a kernel struct's layout out of /sys/kernel/btf/vmlinux.
# A program file's body asks it for three structs and writes what it answered beside the object;
# the case compares that with `bpftool btf dump file /sys/kernel/btf/vmlinux format raw`, the
# same BTF read by a different program.
#   - the size of xdp_md and of __sk_buff, and the byte offset of every field the context
#     proxies expose, match the dump's bits_offset divided by eight; the reader walks a flat
#     stream of variable-length records, so a mis-sized record shifts every offset after it
#   - each of those fields is four bytes, which is the only width the kernel lets a program use
#     on either context (net/core/filter.c's __is_valid_xdp_access and bpf_skb_is_valid_access)
#   - iphdr's whole-byte members are reported at the dump's offsets, while the dump's named
#     bitfields and its anonymous union are absent from the layout
#   - a struct the kernel does not publish raises a message naming it
#
# Usage: sudo bash tests/luaebpf/btfview.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 4

DUMP=
LAYOUT=

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
ktap_pass "luaebpf: a bitfield and an anonymous union are absent, and the whole-byte members are not"

grep -q "^missing	false	the kernel BTF has no struct 'a_struct_no_kernel_publishes'$" "$LAYOUT" \
	|| { comment "$(grep '^missing' "$LAYOUT")"; fail "luaebpf: an unpublished struct does not raise with its name"; }
ktap_pass "luaebpf: a struct the kernel does not publish raises a message naming it"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

