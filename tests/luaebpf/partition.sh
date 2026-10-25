#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the shape the call into the kernel Lua runtime is for, examples/sniclassify/classify.c's: a
# TC program decides a flow its hash map holds, walks the headers of one it does not, calls the
# runtime only for a packet the walk accepts, and keeps the priority the callback set. partition.lua
# is the runtime, whose callback sets the skb's priority to the argument it was handed, counts its
# calls in an rcu.table and prints each. The program runs under BPF_PROG_TEST_RUN, whose skb hashes
# to zero, so the two packets of one `repeat 2` are one flow: the first misses the map and the
# second finds it. The program file's body writes what the case expects, from the same packet
# bytes and the same map spec the program was compiled against.
#   - two packets of a ClientHello make one call into Lua, the rcu.table's first: the second is
#     decided from the map
#   - the priority the callback set from its argument is what the map holds and what ctx_out
#     carries back
#   - a SYN to the same port and an ICMP echo, run over a fresh load, make no call and leave the
#     map empty, with the runtime up: the call is where the program put it
# Skips where the kernel publishes no BTF for luatc.
#
# Usage: sudo bash tests/luaebpf/partition.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="partition"
trap cleanup EXIT

SCRIPT=tests/luaebpf/partition
CALLED="luaebpf partition test call"
OK=0
ROWS=3

luaebpf_start $ROWS

reason=$(luaebpf_kfunc luatc)
if [ -n "$reason" ]; then
	for i in $(seq $ROWS); do ktap_skip "luaebpf: $reason"; done
	ktap_totals
	exit 0
fi

# what the program file's body says the case owes
fact() {
	awk -v f="$1" -F'\t' '$1 == f {print $2}' "$LUAEBPF_WORK/facts.txt"
}

# what the map holds under the flow's key, as bpftool prints it, or "absent"
held() {
	local out
	out=$(bpftool map lookup pinned "$LUAEBPF_MAPS/flows" key $(fact key) 2>&1) || { echo absent; return; }
	grep -oP 'value: \K.*' <<< "$out" | sed 's/ *$//'
}

# runs the program over a packet of the corpus <count> times, answering its last verdict
classify() {
	bpftool prog run pinned "$LUAEBPF_PINS/partition" data_in "$LUAEBPF_WORK/$1.bin" \
		ctx_in "$LUAEBPF_WORK/$1.ctx" ctx_out "$LUAEBPF_WORK/$1.out" repeat "$2" 2>&1 \
		| grep -oP 'Return value: \K[0-9]+'
}

output=$(luaebpf_compile partition) || { comment "$output"; fail "luaebpf: partition.bpf.lua did not compile"; }
output=$(luaebpf_loadall partition) || { comment "$output"; fail "luaebpf: the classifier did not verify"; }
output=$(lunatik run --context=softirq "$SCRIPT" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the runtime did not start"; }

tls=$(classify tls 2)
calls=$(dmesg_since | grep -c "$CALLED")
first=$(dmesg_since | grep -cF "$CALLED 1: priority $(fact priority)")
cached=$(held)
carried=$(od -An -tu4 -j "$(fact offset)" -N 4 "$LUAEBPF_WORK/tls.out" | tr -d ' ')

rm -rf "$LUAEBPF_PINS"
output=$(luaebpf_loadall partition) || { comment "$output"; fail "luaebpf: the classifier did not load again"; }
syn=$(classify syn 1)
icmp=$(classify icmp 1)
rejected=$(( $(dmesg_since | grep -c "$CALLED") - calls ))
left=$(held)
lunatik stop "$SCRIPT" > /dev/null 2>&1
rm -rf "$LUAEBPF_PINS"

[ "$tls" = "$OK" ] || fail "luaebpf: the ClientHello answered '$tls', not OK"
[ "$calls" -eq 1 ] && [ "$first" -eq 1 ] || fail "luaebpf: two packets of one flow made $calls calls into Lua, not 1"
ktap_pass "luaebpf: the first packet of a flow calls Lua and the second is decided from the map"

[ "$cached" = "$(fact value)" ] || fail "luaebpf: the map holds '$cached', not '$(fact value)'"
[ "$carried" = "$(fact priority)" ] || fail "luaebpf: ctx_out carries priority '$carried', not '$(fact priority)'"
ktap_pass "luaebpf: the priority the callback set is what the map holds and what ctx_out carries"

[ "$syn" = "$OK" ] && [ "$icmp" = "$OK" ] || fail "luaebpf: the SYN answered '$syn' and the echo '$icmp', not OK"
[ "$rejected" -eq 0 ] || fail "luaebpf: packets the walk rejects made $rejected calls into Lua"
[ "$left" = absent ] || fail "luaebpf: packets the walk rejects left '$left' in the map"
ktap_pass "luaebpf: a packet the header walk rejects never reaches Lua and caches nothing"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

