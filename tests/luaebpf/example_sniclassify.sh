#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests examples/sniclassify as its README runs it: the HTB examples/sniclassify/setup.sh puts on a
# device, then `lunatik run --context=softirq --percpu --dev=`, which attaches the TC program `make
# install` compiled from examples/sniclassify/sni.bpf.lua to the device's egress beside the kernel
# script that classifies by the SNI, on the host's end of a veth pair whose peer sits in a namespace
# of the case's own, and curl, run on the host, connects to a listener in the namespace.
#   - the ClientHellos curl sends naming zoom.com and netflix.com, each over a connection of its own,
#     reach the listener, and the script logs each once with the class its policy names: the program
#     calls it on the first pushed segment of each flow, whose hash keys its map
#   - the packets of each connection after its ClientHello go out in the class the script set, which
#     the program takes from its map: each class counts more packets than the ClientHello
# Skips where the example's object is not installed, which `make install` compiles where the kernel
# publishes BTF, where luatc publishes none, without socat, curl or tc, where the kernel's
# configuration lacks CONFIG_NET_SCH_HTB, and where the CLI's loader names a libbpf older than tcx.
#
# Usage: sudo bash tests/luaebpf/example_sniclassify.sh

SCRIPT="examples/sniclassify/sni"
OBJECT="/usr/local/lib/bpf/luaebpf/$SCRIPT.bpf.o"
NETNS="lunatik_sniclassify"
HOST="10.195.0.1"
TARGET="10.195.0.2"
MAC="02:00:00:00:c3:01"
PORT=443
TIMEOUT=3 # seconds
ZOOM="zoom.com"       # 1:10 in the policy of examples/sniclassify/sni.lua
ZOOMCLASS="1:10"
ZOOMID=$((0x10010))   # the classid the script logs for it
NETFLIX="netflix.com" # 1:30 there
NETFLIXCLASS="1:30"
NETFLIXID=$((0x10030))
NOTCX="tcx needs libbpf 1.3.0" # lualoader_open, luaebpf/loader.c
TITLE_HELLO="luaebpf: examples/sniclassify classifies the ClientHello of each connection by its SNI"
TITLE_FLOW="luaebpf: examples/sniclassify sends the rest of a connection in its class, from the map"

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

# common.sh's cleanup, and the run, the namespace and the listener the case adds; the device takes
# its HTB with it
teardown() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	pkill -f "TCP-LISTEN:$PORT,bind=$TARGET" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	cleanup
}

# the HTB examples/sniclassify/setup.sh puts on the device
classes() {
	tc qdisc add dev "$LUAEBPF_DEV" root handle 1: htb default 20 &&
	tc class add dev "$LUAEBPF_DEV" parent 1:  classid 1:1  htb rate 100mbit ceil 100mbit &&
	tc class add dev "$LUAEBPF_DEV" parent 1:1 classid 1:10 htb rate 50mbit  ceil 100mbit prio 1 &&
	tc class add dev "$LUAEBPF_DEV" parent 1:1 classid 1:20 htb rate 30mbit  ceil 100mbit prio 2 &&
	tc class add dev "$LUAEBPF_DEV" parent 1:1 classid 1:30 htb rate 20mbit  ceil 100mbit prio 3
}

# the packets the HTB class <classid> sent
counted() {
	tc -s class show dev "$LUAEBPF_DEV" classid "$1" | grep -oP 'Sent [0-9]+ bytes \K[0-9]+(?= pkt)'
}

# sends <classid> <n>: the class sent <n> packets or more
sends() {
	[ "$(counted "$1")" -ge "$2" ] 2>/dev/null
}

listening() {
	ip netns exec "$NETNS" ss -Hltn "sport = :$PORT" | grep -q .
}

ended() {
	! kill -0 "$listener" 2>/dev/null
}

# delivered <host>: how many bytes a listener in the namespace received of the ClientHello curl sends
# from the host to <host>, resolved to the listener, stopped once curl has gone, or nothing where it
# accepted no connection; the listener answers nothing, so curl gives up after TIMEOUT
delivered() {
	rm -f "$LUAEBPF_WORK/received"
	ip netns exec "$NETNS" socat -u "TCP-LISTEN:$PORT,bind=$TARGET,reuseaddr" "CREATE:$LUAEBPF_WORK/received" &
	listener=$!
	awaited listening
	curl -so /dev/null --max-time "$TIMEOUT" --resolve "$1:$PORT:$TARGET" "https://$1"
	awaited ended
	kill "$listener" 2>/dev/null
	wait "$listener" 2>/dev/null
	stat -c %s "$LUAEBPF_WORK/received" 2>/dev/null
}

trap teardown EXIT
teardown

luaebpf_start 2 luatc
[ -r "$OBJECT" ] || skip_script "luaebpf: $OBJECT is not installed; run make install on a kernel with BTF"
for tool in socat curl tc; do
	command -v "$tool" > /dev/null || skip_script "luaebpf: $tool is not installed"
done
lacks CONFIG_NET_SCH_HTB && skip_script "luaebpf: the example's HTB needs CONFIG_NET_SCH_HTB"

ip netns add "$NETNS"
# a fixed address: a random one is one a host process may replace once the namespace learned it
ip link add "$LUAEBPF_DEV" address "$MAC" type veth peer name "$LUAEBPF_PEER"
ip link set "$LUAEBPF_PEER" netns "$NETNS"
ip addr add "$HOST/24" dev "$LUAEBPF_DEV"
ip link set "$LUAEBPF_DEV" up
ip netns exec "$NETNS" ip addr add "$TARGET/24" dev "$LUAEBPF_PEER"
ip netns exec "$NETNS" ip link set "$LUAEBPF_PEER" up
output=$(classes 2>&1) \
	|| { comment "$output"; fail "luaebpf: the HTB of examples/sniclassify/setup.sh could not be set up"; }

mark_dmesg
output=$(lunatik run --context=softirq --percpu --dev="$LUAEBPF_DEV" "$SCRIPT" 2>&1)
status=$?
grep -qF "$NOTCX" <<< "$output" && skip_script "luaebpf: $NOTCX"
[ $status -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: $SCRIPT did not run"; }

zoomed=$(delivered "$ZOOM")
netflixed=$(delivered "$NETFLIX")
zoomlogged=$(dmesg_since | grep -cF "sniclassify: $ZOOM $ZOOMID")
netflixlogged=$(dmesg_since | grep -cF "sniclassify: $NETFLIX $NETFLIXID")
awaited sends "$ZOOMCLASS" 2
awaited sends "$NETFLIXCLASS" 2
zoomcounted=$(counted "$ZOOMCLASS")
netflixcounted=$(counted "$NETFLIXCLASS")

teardown

if [ "${zoomed:-0}" -eq 0 ] || [ "${netflixed:-0}" -eq 0 ]; then
	comment "$ZOOM: '${zoomed:-no connection}' bytes, $NETFLIX: '${netflixed:-no connection}'"
	ktap_fail "$TITLE_HELLO: the listener did not receive both"
elif [ "$zoomlogged" -ne 1 ] || [ "$netflixlogged" -ne 1 ]; then
	ktap_fail "$TITLE_HELLO: the script logged $ZOOM $zoomlogged times and $NETFLIX $netflixlogged times, not once each"
else
	ktap_pass "$TITLE_HELLO"
fi

if [ "${zoomcounted:-0}" -lt 2 ] || [ "${netflixcounted:-0}" -lt 2 ]; then
	comment "$ZOOMCLASS sent ${zoomcounted:-nothing} packets, $NETFLIXCLASS ${netflixcounted:-nothing}"
	ktap_fail "$TITLE_FLOW: a class did not send its ClientHello and a packet after it"
else
	ktap_pass "$TITLE_FLOW"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

