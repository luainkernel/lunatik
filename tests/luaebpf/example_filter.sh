#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests examples/filter as its README runs it: `lunatik run --context=softirq --percpu --dev=` loads
# the XDP program `make install` compiled from examples/filter/sni.bpf.lua and the kernel script that
# parses the SNI, on the host's end of a veth pair whose peer sits in a namespace of the case's own,
# and curl, run in the namespace, connects to a listener on the host's end.
#   - a ClientHello naming another host than ebpf.io reaches the listener, and the script logs it PASS
#   - a ClientHello naming ebpf.io, the host the script blocks, never reaches the listener, though the
#     connection does, and the script logs it DROP
#   - the stop takes the program off the device, and the runtime and the pins down
# Skips where the example's object is not installed, which `make install` compiles where the kernel
# publishes BTF, where luaxdp publishes none, and without socat or curl; the two ClientHellos skip
# where something already listens on port 443.
#
# Usage: sudo bash tests/luaebpf/example_filter.sh

SCRIPT="examples/filter/sni"
OBJECT="/usr/local/lib/bpf/luaebpf/$SCRIPT.bpf.o"
ROOT="/sys/fs/bpf/lunatik/$SCRIPT"
NETNS="lunatik_filter"
HOST="10.196.0.1"
TARGET="10.196.0.2"
MAC="02:00:00:00:c4:01"
PORT=443
TIMEOUT=3 # seconds
BLOCKED="ebpf.io" # the blacklist of examples/filter/sni.lua
ALLOWED="example.com"
TITLE_PASS="luaebpf: examples/filter lets a ClientHello naming another host reach its listener"
TITLE_DROP="luaebpf: examples/filter drops a ClientHello naming the blocked host"
TITLE_STOP="luaebpf: examples/filter's stop takes the program, the runtime and the pins down"

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

# common.sh's cleanup, and the run, the namespace and the listener the case adds
teardown() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	pkill -f "TCP-LISTEN:$PORT,bind=$HOST" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	cleanup
}

ended() {
	! kill -0 "$listener" 2>/dev/null
}

# delivered <host>: how many bytes a listener on the host's end received of the ClientHello curl sends
# from the namespace to <host>, resolved to the host's end, stopped once curl has gone, as one whose
# segment was dropped never ends, or nothing where it accepted no connection; the listener answers
# nothing, so curl gives up after TIMEOUT
delivered() {
	rm -f "$LUAEBPF_WORK/received"
	socat -u "TCP-LISTEN:$PORT,bind=$HOST,reuseaddr" "CREATE:$LUAEBPF_WORK/received" &
	listener=$!
	awaited listens -t "$PORT"
	ip netns exec "$NETNS" curl -s --max-time "$TIMEOUT" --resolve "$1:$PORT:$HOST" "https://$1" > /dev/null
	awaited ended
	kill "$listener" 2>/dev/null
	wait "$listener" 2>/dev/null
	stat -c %s "$LUAEBPF_WORK/received" 2>/dev/null
}

trap teardown EXIT
teardown

luaebpf_start 3 luaxdp
[ -r "$OBJECT" ] || skip_script "luaebpf: $OBJECT is not installed; run make install on a kernel with BTF"
command -v socat > /dev/null || skip_script "luaebpf: socat is not installed"
command -v curl > /dev/null || skip_script "luaebpf: curl is not installed"

ip netns add "$NETNS"
# a fixed address: a random one is one a host process may replace once the namespace learned it
ip link add "$LUAEBPF_DEV" address "$MAC" type veth peer name "$LUAEBPF_PEER"
ip link set "$LUAEBPF_PEER" netns "$NETNS"
ip addr add "$HOST/24" dev "$LUAEBPF_DEV"
ip link set "$LUAEBPF_DEV" up
ip netns exec "$NETNS" ip addr add "$TARGET/24" dev "$LUAEBPF_PEER"
ip netns exec "$NETNS" ip link set "$LUAEBPF_PEER" up

mark_dmesg
output=$(lunatik run --context=softirq --percpu --dev="$LUAEBPF_DEV" "$SCRIPT" 2>&1)
[ $? -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: $SCRIPT did not run"; }

if listens -t "$PORT"; then
	held=yes
else
	allowed=$(delivered "$ALLOWED")
	blocked=$(delivered "$BLOCKED")
	passed=$(dmesg_since | grep -cF "filter_sni: $ALLOWED PASS")
	dropped=$(dmesg_since | grep -cF "filter_sni: $BLOCKED DROP")
fi

stopped=$(lunatik stop "$SCRIPT" 2>&1)
halted=$?
left=$(ls -d "$ROOT" 2>/dev/null)
attached=$(luaebpf_attached)
listed=$(lunatik list)
teardown

if [ -n "$held" ]; then
	ktap_skip "$TITLE_PASS: something listens on port $PORT"
	ktap_skip "$TITLE_DROP: something listens on port $PORT"
else
	if [ "${allowed:-0}" -eq 0 ]; then
		ktap_fail "$TITLE_PASS: the listener received '${allowed:-no connection}', not the ClientHello"
	elif [ "$passed" -lt 1 ]; then
		ktap_fail "$TITLE_PASS: the script did not log $ALLOWED PASS"
	else
		ktap_pass "$TITLE_PASS"
	fi
	if [ "$blocked" != 0 ]; then
		ktap_fail "$TITLE_DROP: the listener received '${blocked:-no connection}', not a connection and no byte"
	elif [ "$dropped" -lt 1 ]; then
		ktap_fail "$TITLE_DROP: the script did not log $BLOCKED DROP"
	else
		ktap_pass "$TITLE_DROP"
	fi
fi

if [ "$halted" -ne 0 ] || [ -n "$left" ] || [ -n "$attached" ] || grep -qxF "$SCRIPT" <<< "$listed"; then
	comment "$stopped"
	ktap_fail "$TITLE_STOP: it exited $halted, leaving '$left', program '$attached' and runtimes '$listed'"
else
	ktap_pass "$TITLE_STOP"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

