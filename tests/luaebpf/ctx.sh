#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the context proxies: the fields a program reads and writes on its own context. One
# program file declares both kinds, so the object carries an xdp, a tcx/ingress and a tcx/egress
# section and `bpftool prog loadall` reads each program's type off the section it sits in.
#   - an XDP program reads ctx:ingress() and ctx:queue(), the kernel's XDP ctx
#     object's own spelling, and a TC program reads #skb, skb:ifindex() and skb:priority(), the
#     kernel's skb object's: each answers what prog run was told to build the context from. The
#     program file's body writes those bytes at the offsets luaebpf.vmlinux reports, so a wrong
#     offset fills a field the program does not read and prog run answers the other number, or
#     refuses the context outright
#   - skb:hash() compiles and answers 0 on both sides, prog run building its skb with no hash;
#     the offset it reads at is btfview.sh's
#   - skb:priority(n) answers n read back through the kernel's own context, and the case reads
#     ctx_out at the offset the reader gives it and finds the same number; so does a value the
#     program computes from another field, with the field's top bit set, which the store takes
#     from a register, and U32_MAX, the largest the field holds
#   - a value the program computes past 32 bits or below zero, where the kernel's skb:priority
#     raises, takes the default verdict, and ctx_out carries the priority prog run was given
#   - a TC program declared with {egress = true} loads from its own section and reads #skb as
#     the ingress one does
#   - neither context has a field, read or assigned, the xdp_md and __sk_buff fields the proxies
#     read included, and an XDP context has no length; ingress_ifindex, which
#     the kernel's skb object does not carry, and a field the struct does not carry are refused
#     by name, ctx.data and ctx.data_end are refused as the packet bounds they are, and
#     skb:priority takes a number, and one the compiler holds from 0 up to U32_MAX
#   - each context opens its packet under its kernel object's name, so ctx:data() on XDP and
#     skb:packet() on TC are refused as methods the context has not, and skb:data("net") as a
#     layer no compiled read reaches yet
# btfview.sh is what ties those offsets to the kernel's own BTF; this case ties them to what the
# kernel does with them.
#
# Usage: sudo bash tests/luaebpf/ctx.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 19

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
got=$(luaebpf_keeps skbsetprio skbwrite "$LUAEBPF_WORK/skbwrite.out")
[ "$got" = "$want" ] || fail "luaebpf: the priority write answered '$got', not '$want'"
out=$(od -An -tu4 -j "$at" -N 4 "$LUAEBPF_WORK/skbwrite.out" | tr -d ' ')
[ "$out" = "$want" ] || fail "luaebpf: ctx_out carries priority '$out' at offset $at, not '$want'"
ktap_pass "luaebpf: what skb:priority(v) stores is what ctx_out carries back"

want=$(reported held)
got=$(luaebpf_verdict skbsetwide skbctx "$LUAEBPF_WORK/skbwide.out")
[ "$got" = 0 ] || fail "luaebpf: a priority past 32 bits answered '$got', not the default verdict"
out=$(od -An -tu4 -j "$at" -N 4 "$LUAEBPF_WORK/skbwide.out" | tr -d ' ')
[ "$out" = "$want" ] || fail "luaebpf: a priority past 32 bits left '$out' in ctx_out, not '$want'"
ktap_pass "luaebpf: a priority past 32 bits takes the default verdict and leaves the priority as it was"

got=$(luaebpf_keeps skbegress skbctx)
want=$(luaebpf_keeps skblen skbctx)
[ -n "$got" ] && [ "$got" = "$want" ] || fail "luaebpf: the egress program answered '$got', the ingress one '$want'"
ktap_pass "luaebpf: an egress program loads from its own section and reads the context"

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

row ctxfield xdp "the context has no field 'ingress_ifindex'" $'\treturn ctx.ingress_ifindex'
row ctxwrite xdp "the context has no field 'rx_queue_index'" $'\tctx.rx_queue_index = 3\n\treturn 0'
row ctxunknown xdp "the context has no field 'mark'" $'\treturn ctx.mark'
row ctxdata xdp "'data' is a packet bound, not a number; '#' on the packet is its length" \
	$'\treturn ctx.data'
row ctxlen xdp "the context has no length; '#' on the packet is its length" $'\treturn #ctx'
row skbfield tc "the context has no field 'len'" $'\treturn ctx.len'
row skbassign tc "the context has no field 'priority'" $'\tctx.priority = 3\n\treturn 0'
row skbingress tc "the context has no field 'ingress_ifindex'" $'\treturn ctx.ingress_ifindex'
row skbprioboolean tc "'priority' takes a number, not a boolean" $'\tctx:priority(true)\n\treturn 0'
row skbpriowide tc "'priority' takes 0 to 4294967295, not 4294967296" \
	$'\tctx:priority(0x100000000)\n\treturn 0'
row skbprionegative tc "'priority' takes 0 to 4294967295, not -1" $'\tctx:priority(-1)\n\treturn 0'
row ctxdatamethod xdp "the context has no method 'data'" $'\tlocal p = ctx:data()\n\treturn #p'
row skbpacket tc "the context has no method 'packet'" $'\tlocal p = ctx:packet()\n\treturn #p'
row skblayer tc "'data' with a layer is not compiled yet" $'\tlocal p = ctx:data("net")\n\treturn #p'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

