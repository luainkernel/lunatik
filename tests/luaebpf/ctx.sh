#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the context proxies: the fields a program reads and writes on its own context. One
# program file declares both kinds, so the object carries an xdp, a tcx/ingress and a tcx/egress
# section and `bpftool prog loadall` reads each program's type off the section it sits in.
#   - an XDP program reads ctx:ingress() and ctx:queue(), the kernel's XDP ctx
#     object's own spelling, and a TC program reads #skb, skb:ifindex(), skb:mark() and
#     skb:priority(), the kernel's skb object's: each answers what prog run was told to build the
#     context from. The program file's body writes those bytes at the offsets bpf.vmlinux reports,
#     so a wrong offset fills a field the program does not read and the program keeps the other
#     number, or prog run refuses the context outright
#   - skb:hash() compiles and answers 0 on both sides, prog run building its skb with no hash;
#     the offset it reads at is btfview.sh's
#   - skb:priority(n) answers n read back through the kernel's own context, and the case reads
#     ctx_out at the offset the reader gives it and finds the same number; so does a value the
#     program computes from another field, with the field's top bit set, which the store takes
#     from a register, and U32_MAX, the largest the field holds. skb:mark(n) answers n and ctx_out
#     carries it, and a computed value with the top bit set is answered whole; prog run is given a
#     mark apart from the priority, so a read or a write of the other field answers another number
#   - a value the program computes past 32 bits or below zero, where the kernel's skb:priority
#     and skb:mark raise, returns TC_ACT_SHOT, and ctx_out carries the priority, or the mark, prog
#     run was given; one run of each writes into the trace ring "out of bounds", as
#     lunatik_checkbounds raises it, at its line, once and alone, and counts one stop at that line's
#     place and none at another
#   - a TC program declared with {egress = true} loads from its own section and reads #skb as
#     the ingress one does
#   - neither context has a field, read or assigned, the xdp_md and __sk_buff fields the proxies
#     read included, and an XDP context has no length; ingress_ifindex, which
#     the kernel's skb object does not carry, and a field the struct does not carry are refused
#     by name, ctx.data and ctx.data_end are refused as the packet bounds they are, and
#     skb:priority and skb:mark take a number, and one the compiler holds from 0 up to U32_MAX; a
#     method the kernel's skb object has and the context does not, skb:connmark(), is refused by
#     name
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

luaebpf_start 28

BOUNDS="out of bounds" # lunatik_checkbounds, lunatik.h

# the line each priority out of bounds logs, the first stops of the object
priorities() {
	luaebpf_logs skbsetwide "$(luaebpf_logline ctx "skb:priority(#skb + U32MAX)" "$BOUNDS")" skbctx
	luaebpf_logs skbsetneg "$(luaebpf_logline ctx "skb:priority(-#skb)" "$BOUNDS")" skbctx
}

# the line each mark out of bounds logs
marks() {
	luaebpf_logs skbsetmarkwide "$(luaebpf_logline ctx "skb:mark(#skb + U32MAX)" "$BOUNDS")" skbctx
	luaebpf_logs skbsetmarkneg "$(luaebpf_logline ctx "skb:mark(-#skb)" "$BOUNDS")" skbctx
}

output=$(luaebpf_compile ctx) || { comment "$output"; fail "luaebpf: ctx.bpf.lua did not compile"; }
output=$(luaebpf_loadall ctx) || { comment "$output"; fail "luaebpf: the context reads did not verify"; }
ktap_pass "luaebpf: every context row verifies"

luaebpf_logcase "a priority out of bounds logs its file and line once" priorities
luaebpf_logcase "a mark out of bounds logs its file and line once" marks

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
[ "$got" = 2 ] || fail "luaebpf: a priority past 32 bits answered '$got', not TC_ACT_SHOT, 2"
out=$(od -An -tu4 -j "$at" -N 4 "$LUAEBPF_WORK/skbwide.out" | tr -d ' ')
[ "$out" = "$want" ] || fail "luaebpf: a priority past 32 bits left '$out' in ctx_out, not '$want'"
ktap_pass "luaebpf: a priority past 32 bits returns TC_ACT_SHOT and leaves the priority as it was"

at=$(reported mark)
want=$(reported written)
got=$(luaebpf_keeps skbsetmark skbmarkwrite "$LUAEBPF_WORK/skbmarkwrite.out")
[ "$got" = "$want" ] || fail "luaebpf: the mark write answered '$got', not '$want'"
out=$(od -An -tu4 -j "$at" -N 4 "$LUAEBPF_WORK/skbmarkwrite.out" | tr -d ' ')
[ "$out" = "$want" ] || fail "luaebpf: ctx_out carries mark '$out' at offset $at, not '$want'"
ktap_pass "luaebpf: what skb:mark(v) stores is what ctx_out carries back"

want=$(reported marked)
got=$(luaebpf_verdict skbsetmarkneg skbctx "$LUAEBPF_WORK/skbmarkneg.out")
[ "$got" = 2 ] || fail "luaebpf: a mark below zero answered '$got', not TC_ACT_SHOT, 2"
out=$(od -An -tu4 -j "$at" -N 4 "$LUAEBPF_WORK/skbmarkneg.out" | tr -d ' ')
[ "$out" = "$want" ] || fail "luaebpf: a mark below zero left '$out' in ctx_out, not '$want'"
ktap_pass "luaebpf: a mark below zero returns TC_ACT_SHOT and leaves the mark as it was"

got=$(luaebpf_keeps skbegress skbctx)
want=$(luaebpf_keeps skblen skbctx)
[ -n "$got" ] && [ "$got" = "$want" ] || fail "luaebpf: the egress program answered '$got', the ingress one '$want'"
ktap_pass "luaebpf: an egress program loads from its own section and reads the context"

# every row is one compiled function over the context, so only the body and the module differ
row() {
	local name="$1" module="$2" message="$3" body="$4" default=PASS
	[ "$module" = tc ] && default=OK
	{
		echo "local bpf = require(\"bpf.$module\")"
		echo "local action = require(\"linux.$module\").action"
		echo 'return bpf.program(function(ctx)'
		echo "$body"
		echo "end, {default = action.$default})"
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
row skbmarkassign tc "the context has no field 'mark'" $'\tctx.mark = 1\n\treturn 0'
row skbmarkboolean tc "'mark' takes a number, not a boolean" $'\tctx:mark(true)\n\treturn 0'
row skbmarkwide tc "'mark' takes 0 to 4294967295, not 4294967296" \
	$'\tctx:mark(0x100000000)\n\treturn 0'
row skbmarknegative tc "'mark' takes 0 to 4294967295, not -1" $'\tctx:mark(-1)\n\treturn 0'
row skbconnmark tc "the context has no method 'connmark'" $'\tlocal m = ctx:connmark()\n\treturn m'
row ctxdatamethod xdp "the context has no method 'data'" $'\tlocal p = ctx:data()\n\treturn #p'
row skbpacket tc "the context has no method 'packet'" $'\tlocal p = ctx:packet()\n\treturn #p'
row skblayer tc "'data' with a layer is not compiled yet" $'\tlocal p = ctx:data("net")\n\treturn #p'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

