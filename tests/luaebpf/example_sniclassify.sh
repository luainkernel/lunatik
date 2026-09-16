#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests examples/sniclassify deployed as the tree ships it: the htb classes
# examples/sniclassify/setup.sh installs, on a veth pair of the case's own, and the one
# `lunatik run` that pins the flow map, starts the runtime the program calls, loads the compiled
# classifier and attaches it to the egress hook.
#   - the kernel-side fixture puts an ICMP echo and then two ClientHellos of one flow on
#     classify0 with a raw socket, so they leave through tcx egress and then htb. A locally
#     generated skb reaches sch_handle_egress before netdev_core_pick_tx computes its hash, so
#     every frame of the run carries hash zero and the three are one flow to the program
#   - exactly one `sniclassify: <host> <classid>` line: the first ClientHello called Lua, the
#     second was decided from the map, and the ICMP echo the header walk rejects never reached
#     the call, which is what says the call is where the program put it and not on every packet
#   - the flow map holds the classid the callback set, which says the compiled side read
#     skb.priority back after the call rather than assuming what the callback would do
#   - the htb class the policy names counts both ClientHellos and the prioritised class counts
#     none, as a delta around the sends: the priority the program set is what htb classified on,
#     which is the example's whole claim, and the frame the walk rejected is not among them
#   - the CLI's stop leaves no pin root, no runtime and nothing on classify0
# The policy and the default class are read as lower bounds, since a veth the machine has just
# brought up may carry solicitations of its own: the flow key is the skb hash, zero for every
# locally generated frame, so a stray one leaving in the window takes the classid the first
# ClientHello cached. The prioritised class stays exact, because nothing gives a frame that priority
# and a cached decision names the policy. Every measurement is taken before the first check and the
# example is stopped before them all, so a failing row leaves the next case nothing.
#
# Usage: sudo bash tests/luaebpf/example_sniclassify.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

SCRIPT=tests/luaebpf/example_sniclassify
DEV=$LUAEBPF_CLASSIFYDEV
OBJECT=/lib/modules/lua/$LUAEBPF_CLASSIFY.bpf.o
MAP=$LUAEBPF_DEPLOY/$LUAEBPF_CLASSIFY/flows
CALLED="sniclassify: netflix.com"
# the key a frame of hash zero takes and the classid the policy gives netflix.com, both as
# bpftool prints an I4
ZEROKEY="0 0 0 0"
CLASSID="30 00 01 00"
POLICY=1:30
PRIOR=1:10
DEFAULT=1:20
FLOW=2
PLAN=4

luaebpf_start "$PLAN"

[ -r "$OBJECT" ] || luaebpf_skipall "$PLAN" "$OBJECT is not installed"
command -v tc >/dev/null || luaebpf_skipall "$PLAN" "tc is not installed"
gate=$(luaebpf_kfunc luatc bpf_luatc_run)
[ -z "$gate" ] || luaebpf_skipall "$PLAN" "$gate"
luaebpf_device "$DEV" "$LUAEBPF_CLASSIFYPEER" \
	|| luaebpf_skipall "$PLAN" "the case could not create $DEV"

# the qdisc and the classes examples/sniclassify/setup.sh installs
output=$(tc qdisc add dev "$DEV" root handle 1: htb default 20 2>&1) \
	|| luaebpf_skipall "$PLAN" "the kernel will not add an htb qdisc: $output"
tc class add dev "$DEV" parent 1:  classid 1:1  htb rate 100mbit ceil 100mbit 2>/dev/null
tc class add dev "$DEV" parent 1:1 classid $PRIOR   htb rate 50mbit ceil 100mbit prio 1 2>/dev/null
tc class add dev "$DEV" parent 1:1 classid $DEFAULT htb rate 30mbit ceil 100mbit prio 2 2>/dev/null
tc class add dev "$DEV" parent 1:1 classid $POLICY  htb rate 20mbit ceil 100mbit prio 3 2>/dev/null

# what the htb class of that id has sent, in packets
sent() {
	tc -s class show dev "$DEV" \
		| awk -v id="class htb $1 " 'index($0, id) == 1 {seen = 1; next} seen && $1 == "Sent" {print $4; exit}'
}

# what the flow map holds under the key every frame of the run takes, or "absent"
held() {
	local out
	out=$(bpftool map lookup pinned "$MAP" key $ZEROKEY 2>&1) || { echo absent; return; }
	echo "$out" | grep -oP 'value: \K.*' | sed 's/ *$//'
}

[ -n "$(sent $POLICY)" ] || luaebpf_skipall "$PLAN" "the kernel took no htb class on $DEV"

before_policy=$(sent $POLICY)
before_prior=$(sent $PRIOR)
before_default=$(sent $DEFAULT)

mark_dmesg
deployed=$(lunatik run "$LUAEBPF_CLASSIFY" softirq percpu dev="$DEV" 2>&1)
output=$(lunatik run "$SCRIPT" 2>&1)
lunatik stop "$SCRIPT" > /dev/null 2>&1

calls=$(dmesg_since | grep -c "$CALLED")
cached=$(held)
policy=$(($(sent $POLICY) - before_policy))
prior=$(($(sent $PRIOR) - before_prior))
default=$(($(sent $DEFAULT) - before_default))

lunatik stop "$LUAEBPF_CLASSIFY" > /dev/null 2>&1
left=$(luaebpf_residue "$LUAEBPF_CLASSIFY" "$DEV")

[ -z "$deployed" ] || { comment "$deployed"; fail "luaebpf: the example did not deploy"; }
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the fixture did not run"; }

[ "$calls" -eq 1 ] || fail "luaebpf: three frames of one flow made $calls calls into Lua, not 1"
ktap_pass "luaebpf: the first ClientHello of a flow calls Lua, the second and the echo do not"

[ "$cached" = "$CLASSID" ] || fail "luaebpf: the flow map holds '$cached', not '$CLASSID'"
ktap_pass "luaebpf: the classid the callback set is what the compiled side cached"

[ "$policy" -ge "$FLOW" ] || fail "luaebpf: htb sent $policy packets in $POLICY, fewer than $FLOW"
[ "$prior" -eq 0 ] || fail "luaebpf: htb sent $prior packets in $PRIOR, which no frame was given"
[ "$default" -ge 1 ] || fail "luaebpf: htb sent no packet in $DEFAULT, where the echo belongs"
ktap_pass "luaebpf: htb classified both ClientHellos on the priority the program set"

[ -z "$left" ] || fail "luaebpf: the stop left$left"
ktap_pass "luaebpf: the CLI's stop takes the example off the device and out of the pin root"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

