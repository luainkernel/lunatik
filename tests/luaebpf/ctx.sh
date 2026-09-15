#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the context proxy: the fields a program reads off its own context.
#   - an XDP program reads ctx.ingress_ifindex and ctx.rx_queue_index and answers what prog run
#     was told to build the context from. The program file's body writes those bytes at the
#     offsets luaebpf.vmlinux reports, so a wrong offset fills a field the program does not read
#     and prog run answers the other number, or refuses the context outright
#   - no XDP field is writable, a field the struct does not carry is refused by name, and
#     ctx.data and ctx.data_end are refused as the packet bounds they are
# btfview.sh is what ties those offsets to the kernel's own BTF; this case ties them to what the
# kernel does with them.
#
# Usage: sudo bash tests/luaebpf/ctx.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 5

output=$(luaebpf_compile ctx) || { comment "$output"; fail "luaebpf: ctx.bpf.lua did not compile"; }
output=$(luaebpf_loadall ctx) || { comment "$output"; fail "luaebpf: the context reads did not verify"; }
ktap_pass "luaebpf: every context row verifies"

output=$(luaebpf_differential) || { comment "$output"; fail "luaebpf: a context field differs"; }
ktap_pass "luaebpf: every context field reads back what prog run was given"

# every row is one compiled function over the context, so only the body differs
row() {
	local name="$1" message="$2" body="$3"
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo 'return xdp.program(function(ctx)'
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

row ctxwrite "the context field 'rx_queue_index' cannot be written" \
	$'\tctx.rx_queue_index = 3\n\treturn 0'
row ctxunknown "the context has no field 'mark'" $'\treturn ctx.mark'
row ctxdata "'data' is a packet bound, not a number; '#' on the packet is its length" \
	$'\treturn ctx.data'

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

