#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the context proxies: the fields a program reads and writes on its own context. One
# program file declares both kinds, so the object carries an xdp and a tcx/ingress section and
# `bpftool prog loadall` reads each program's type off the section it sits in.
#   - an XDP program reads ctx.ingress_ifindex and ctx.rx_queue_index, and a TC program reads
#     skb.len, skb.ifindex, skb.ingress_ifindex and skb.priority: each answers what prog run was
#     told to build the context from. The program file's body writes those bytes at the offsets
#     luaebpf.vmlinux reports, so a wrong offset fills a field the program does not read and
#     prog run answers the other number, or refuses the context outright
#   - skb.hash reads 0. prog run cannot supply a hash: it sits in a range convert___skb_to_skb
#     makes ctx_in leave zero, and the skb it builds has none. The row is there for the read,
#     and what says the read is at the right offset is btfview.sh and the refusals beside it,
#     not the number
#   - skb.priority = n comes back through the kernel's own context on the next read, and the
#     case reads ctx_out at the offset the reader gives it and finds the same number
#   - no XDP field is writable, skb.len is not in the set the kernel takes a write on, a field
#     the struct does not carry is refused by name, ctx.data and ctx.data_end are refused as the
#     packet bounds they are, and a context field takes a number
# btfview.sh is what ties those offsets to the kernel's own BTF; this case ties them to what the
# kernel does with them.
#
# Usage: sudo bash tests/luaebpf/ctx.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 8

output=$(luaebpf_compile ctx) || { comment "$output"; fail "luaebpf: ctx.bpf.lua did not compile"; }
output=$(luaebpf_loadall ctx) || { comment "$output"; fail "luaebpf: the context reads did not verify"; }
ktap_pass "luaebpf: every context row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a context field differs"; }
ktap_pass "luaebpf: every context field reads back what prog run was given"

# what the program file reported for one __sk_buff member
reported() {
	awk -v f="$1" '$1 == f {print $2}' "$LUAEBPF_WORK/offsets.txt"
}

at=$(reported priority)
want=$(reported written)
got=$(luaebpf_verdict skbsetprio skbwrite "$LUAEBPF_WORK/skbwrite.out")
[ "$got" = "$want" ] || fail "luaebpf: the priority write answered '$got', not '$want'"
out=$(od -An -tu4 -j "$at" -N 4 "$LUAEBPF_WORK/skbwrite.out" | tr -d ' ')
[ "$out" = "$want" ] || fail "luaebpf: ctx_out carries priority '$out' at offset $at, not '$want'"
ktap_pass "luaebpf: a write to skb.priority is what ctx_out carries back"

# every row is one compiled function over the context, so only the body and the module differ
row() {
	local name="$1" module="$2" message="$3" body="$4"
	{
		echo "local bpf = require(\"bpf.$module\")"
		echo ''
		echo 'return bpf.program(function(ctx)'
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:4: $message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row ctxwrite xdp "the context field 'rx_queue_index' cannot be written" \
	$'\tctx.rx_queue_index = 3\n\treturn 0'
row ctxunknown xdp "the context has no field 'mark'" $'\treturn ctx.mark'
row ctxdata xdp "'data' is a packet bound, not a number; '#' on the packet is its length" \
	$'\treturn ctx.data'
row skbwritelen tc "the context field 'len' cannot be written" $'\tctx.len = 3\n\treturn 0'
row skbprioboolean tc "the context field 'priority' takes a number, not a boolean" \
	$'\tctx.priority = true\n\treturn 0'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

