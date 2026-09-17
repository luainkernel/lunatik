#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the shape the escape hatch exists for: `examples/sniclassify/classify.c` in Lua. The TC
# program looks a flow up in a hash it declares, calls the kernel runtime only where the lookup
# missed and the headers say the packet is worth it, and caches what the callback decided. The
# oracle is `BPF_PROG_TEST_RUN`, whose `__sk_buff` reads its hash back as zero, so the two
# packets of one `repeat 2` are one flow: the first misses and the second hits.
#   - two packets of the ClientHello, one callback line: the second was decided from the map
#   - the priority the callback set from the argument it was handed is what the pinned map holds
#     and what `ctx_out` carries back, which is what says the argument reached Lua and the
#     write-back read the kernel's own context
#   - a SYN to the same port and an ICMP echo add no callback line and leave the map empty: the
#     call is where the program put it, not on every packet
# The program file's body writes what the case expects, from the same packet bytes and the same
# map spec the program was compiled against. The runtime stays up through the last row on
# purpose: what says the walk rejected a packet is that Lua was reachable and still not called.
# Every check comes after the measurement it reads, and the cleanup in the trap stops the runtime
# and removes the pins, so a failing row leaves the next case nothing.
#
# Usage: sudo bash tests/luaebpf/partition.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

SCRIPT=tests/luaebpf/partition
CALLED="luaebpf partition test call"
ACT_OK=0
ROWS=3

luaebpf_start $ROWS

gate=$(luaebpf_kfunc luatc bpf_luatc_run)
if [ -n "$gate" ]; then
	for i in $(seq $ROWS); do ktap_skip "luaebpf: $gate"; done
	ktap_totals
	exit 0
fi

output=$(luaebpf_compile partition) || { comment "$output"; fail "luaebpf: partition.bpf.lua did not compile"; }
output=$(luaebpf_loadall partition) || { comment "$output"; fail "luaebpf: the classifier did not verify"; }

# what the program file's body says the case owes
fact() {
	awk -v f="$1" -F'\t' '$1 == f {print $2}' "$LUAEBPF_WORK/facts.txt"
}

# what the map holds under the flow's key, as bpftool prints it, or "absent"
held() {
	local out
	out=$(bpftool map lookup pinned "$LUAEBPF_MAPS/flows" key $(fact key) 2>&1) || { echo absent; return; }
	echo "$out" | grep -oP 'value: \K.*' | sed 's/ *$//'
}

# one run of the classifier over a packet of the corpus, answering its verdict
classify() {
	bpftool prog run pinned "$LUAEBPF_PINS/partition" data_in "$LUAEBPF_WORK/$1.bin" \
		ctx_in "$LUAEBPF_WORK/$1.ctx" ctx_out "$LUAEBPF_WORK/$1.out" repeat "$2" 2>&1 \
		| grep -oP 'Return value: \K[0-9]+'
}

mark_dmesg
output=$(lunatik run "$SCRIPT" softirq 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the runtime did not start"; }

verdict=$(classify tls 2)
calls=$(dmesg_since | grep -c "$CALLED")
cached=$(held)
carried=$(od -An -tu4 -j "$(fact offset)" -N 4 "$LUAEBPF_WORK/tls.out" | tr -d ' ')

[ "$verdict" = "$ACT_OK" ] || fail "luaebpf: the ClientHello answered '$verdict', not ACT_OK"
[ "$calls" -eq 1 ] || fail "luaebpf: two packets of one flow made $calls calls into Lua, not 1"
ktap_pass "luaebpf: the first packet of a flow calls Lua and the second is decided from the map"

[ "$cached" = "$(fact value)" ] || fail "luaebpf: the map holds '$cached', not '$(fact value)'"
[ "$carried" = "$(fact priority)" ] \
	|| fail "luaebpf: ctx_out carries priority '$carried', not '$(fact priority)'"
ktap_pass "luaebpf: the priority the callback set is what the map holds and what ctx_out carries"

mark_dmesg
rm -rf "$LUAEBPF_PINS"
output=$(luaebpf_loadall partition) || { comment "$output"; fail "luaebpf: the classifier did not reload"; }
syn=$(classify syn 1)
icmp=$(classify icmp 1)
calls=$(dmesg_since | grep -c "$CALLED")
cached=$(held)
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$syn" = "$ACT_OK" ] || fail "luaebpf: a SYN answered '$syn', not ACT_OK"
[ "$icmp" = "$ACT_OK" ] || fail "luaebpf: an ICMP echo answered '$icmp', not ACT_OK"
[ "$calls" -eq 0 ] || fail "luaebpf: a packet the walk rejects made $calls calls into Lua"
[ "$cached" = absent ] || fail "luaebpf: a packet the walk rejects cached '$cached'"
ktap_pass "luaebpf: a packet the header walk rejects never reaches Lua and caches nothing"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

