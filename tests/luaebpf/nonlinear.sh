#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests skb:data() on an skb that is not linear, which BPF_PROG_TEST_RUN builds only from v6.19:
# the compiled TC program is attached with tc to the egress of a veth pair whose peer sits in a
# network namespace, as the tc suite attaches its own. It lets a packet shorter than PAYLOAD
# bytes out, and opens skb:data() on a longer one and drops it, while its default verdict lets the
# packet out.
#   - a ping shorter than PAYLOAD bytes is answered, and one of PAYLOAD bytes, which
#     ip_append_data builds linear, is dropped: the program runs on what the device sends and
#     opens a linear skb's packet
#   - a TCP segment carrying PAYLOAD bytes from the host to a listener in the namespace, whose
#     payload tcp_sendmsg keeps in page fragments, so that the skb is not linear and the kernel's
#     skb:data() raises on it in a tc callback, reaches the listener: the program took its default
#     verdict at skb:data()
#   - the same program attached at the host side's ingress instead, in a run of its own, answers
#     the same pings and segment the namespace sends the host the same way: cls_bpf pushes the MAC
#     header back before it computes data_end there, and the segment arrives as tcp_sendmsg built it
# The device cases skip without socat or tc.
#
# Usage: sudo bash tests/luaebpf/nonlinear.sh

IFACE="luaebpf0"
PEER="luaebpf1"
NETNS="lunatik_luaebpf"
HOST="10.197.0.1"
TARGET="10.197.0.2"
PORT=5570
PAYLOAD=1024 # PAYLOAD in nonlinear.bpf.lua
LINEAR="luaebpf: a linear skb is opened by skb:data() and answers the program's verdict"
SEGMENT="luaebpf: an skb that is not linear takes the default verdict at skb:data()"
INGRESS=" at ingress"

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

# common.sh's cleanup, and the device, the namespace and the listener the case adds
teardown() {
	tc qdisc del dev "$IFACE" clsact 2>/dev/null
	pkill -f "TCP-LISTEN:$PORT," 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$IFACE" 2>/dev/null
	cleanup
}

# runs a command in the namespace named, or on the host where it names none
inside() {
	local netns="$1"
	shift
	if [ -n "$netns" ]; then
		ip netns exec "$netns" "$@"
	else
		"$@"
	fi
}

listening() {
	inside "$1" ss -Hltn "sport = :$PORT" | grep -q .
}

ended() {
	! kill -0 "$listener" 2>/dev/null
}

# from one side to an address on the other, a ping shorter than PAYLOAD bytes, one of PAYLOAD bytes
# and a segment carrying PAYLOAD bytes to a listener there; sets short, long and received
exchange() {
	local from="$1" to="$2" address="$3"
	inside "$from" ping -c 1 -W 1 "$address" > /dev/null 2>&1
	short=$?
	inside "$from" ping -c 1 -W 1 -s "$PAYLOAD" "$address" > /dev/null 2>&1
	long=$?
	rm -f "$LUAEBPF_WORK/received"
	inside "$to" socat -u "TCP-LISTEN:$PORT,reuseaddr" "CREATE:$LUAEBPF_WORK/received" &
	listener=$!
	awaited listening "$to"
	head -c "$PAYLOAD" /dev/zero | inside "$from" timeout 5 socat -u - "TCP:$address:$PORT" 2>/dev/null
	awaited ended
	received=$(stat -c %s "$LUAEBPF_WORK/received" 2>/dev/null)
}

# what the exchange owes, under the titles with the suffix a run names: the long ping dropped by
# the program's verdict and the segment let through by its default one
verdicts() {
	local where="$1"
	if [ "$short" -ne 0 ]; then
		ktap_fail "$LINEAR$where: a ping shorter than $PAYLOAD bytes was not answered"
	elif [ "$long" -eq 0 ]; then
		ktap_fail "$LINEAR$where: the ping was answered, so the program took its default verdict"
	else
		ktap_pass "$LINEAR$where"
	fi
	if [ "$received" != "$PAYLOAD" ]; then
		ktap_fail "$SEGMENT$where: the listener received '${received:-nothing}', not $PAYLOAD bytes"
	else
		ktap_pass "$SEGMENT$where"
	fi
}

trap teardown EXIT
teardown

luaebpf_start 5

output=$(luaebpf_compile nonlinear) || { comment "$output"; fail "luaebpf: nonlinear.bpf.lua did not compile"; }
output=$(luaebpf_loadall nonlinear) || { comment "$output"; fail "luaebpf: the program did not verify"; }
ktap_pass "luaebpf: a program opening skb:data() verifies"

for tool in socat tc; do
	if ! command -v "$tool" >/dev/null; then
		ktap_skip "$LINEAR: $tool is not installed"
		ktap_skip "$SEGMENT: $tool is not installed"
		ktap_skip "$LINEAR$INGRESS: $tool is not installed"
		ktap_skip "$SEGMENT$INGRESS: $tool is not installed"
		ktap_totals
		exit 0
	fi
done

ip netns add "$NETNS"
ip link add "$IFACE" type veth peer name "$PEER"
ip link set "$PEER" netns "$NETNS"
ip addr add "$HOST/24" dev "$IFACE"
ip link set "$IFACE" up
ip netns exec "$NETNS" ip addr add "$TARGET/24" dev "$PEER"
ip netns exec "$NETNS" ip link set "$PEER" up
tc qdisc add dev "$IFACE" clsact
tc filter add dev "$IFACE" egress bpf da object-pinned "$LUAEBPF_PINS/nonlinear" \
	|| fail "luaebpf: the program could not be attached"
exchange "" "$NETNS" "$TARGET"
verdicts ""

tc filter del dev "$IFACE" egress
tc filter add dev "$IFACE" ingress bpf da object-pinned "$LUAEBPF_PINS/nonlinear" \
	|| fail "luaebpf: the program could not be attached at ingress"
exchange "$NETNS" "" "$HOST"
verdicts "$INGRESS"

teardown

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

