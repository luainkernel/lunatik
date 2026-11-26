#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests examples/filter as its README runs it: `lunatik run --context=softirq --percpu --dev=` loads
# the XDP program `make install` compiled from examples/filter/sni.bpf.lua and the kernel script that
# parses the SNI, on the host's end of a veth pair whose peer sits in a namespace of the case's own.
#   - frames written out of the namespace's end by hand, each carrying a ClientHello and each failing
#     one test the program makes before it calls the script, an EtherType that is not IPv4, an IPv4
#     protocol that is not TCP, a port that is not 443 and a segment without PSH, make no call: no
#     line names their hosts, while the frame that passes every test, written before and after them,
#     is logged both times
#   - a frame of an Ethernet header alone, one of IPv4 that ends with its header, one whose TCP header
#     gives a data offset past its end and a segment with no payload pass without a stop and without a
#     call: `lunatik bpf --errors` reports nothing and the script raises nothing, where a read past
#     the frame stops the program and an offset at or past its end raises in the script
#   - a ClientHello naming another host than ebpf.io, sent from the namespace to a listener on the
#     host's end, reaches it whole, and the script logs it PASS
#   - a ClientHello naming ebpf.io, the host the script blocks, never reaches the listener, though the
#     connection does, and the script logs it DROP
#   - the stop takes the program off the device, and the runtime and the pins down
# Skips where the example's object is not installed, which `make install` compiles where the kernel
# publishes BTF, where luaxdp publishes none, and without socat; the two ClientHellos sent over a
# connection skip where something already listens on port 443.
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
BLOCKED="ebpf.io" # the blacklist of examples/filter/sni.lua
ALLOWED="example.com"
CONTROL="control.example"
IPV4=0x0800
IPV6=0x86dd
TCP=6
UDP=17
PSHACK=0x18
ACK=0x10
WORDS=5    # a TCP header without options
LONGEST=15 # the most words a TCP header gives
ETHER=14
IPHDR=20
TCPHDR=20
TITLE_SKIP="luaebpf: examples/filter hands the script no frame that fails one of its tests"
TITLE_SHORT="luaebpf: examples/filter passes a frame too short for what it reads, with no stop and no call"
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

# forged <host> [<type> <protocol> <port> <flags> <words>]: the TLS record of a ClientHello naming
# <host>, as examples/common/sni.lua parses one, or, given the rest, a broadcast frame of EtherType
# <type> carrying it in an IPv4 packet of <protocol> behind a TCP header to <port>, of <flags> and of
# <words> words, from and to no address
forged() {
	lua5.5 - "$@" <<'LUA'
local pack, rep = string.pack, string.rep

local HANDSHAKE    <const> = 0x16
local RECORD       <const> = 0x0301
local CLIENT_HELLO <const> = 0x01
local VERSION      <const> = 0x0303
local RANDOM       <const> = 32
local SUITE        <const> = 0x1301
local SERVER_NAME  <const> = 0x0000
local HOST_NAME    <const> = 0
local VERSION_IHL  <const> = 0x45
local IPHDR        <const> = 20
local TTL          <const> = 64
local WINDOW       <const> = 0xffff
local HWADDR       <const> = 6
local ADDRESSES    <const> = 8

local host, ethertype, protocol, port, flags, words = arg[1], tonumber(arg[2]), tonumber(arg[3]),
	tonumber(arg[4]), tonumber(arg[5]), tonumber(arg[6])
local extension = pack(">I2 s2", SERVER_NAME, pack(">s2", pack(">B s2", HOST_NAME, host)))
local hello = pack(">I2", VERSION) .. rep("\0", RANDOM) .. pack(">s1 s2 s1 s2", "", pack(">I2", SUITE), "\0", extension)
local record = pack(">B I2 s2", HANDSHAKE, RECORD, pack(">B s3", CLIENT_HELLO, hello))
if ethertype == nil then
	io.write(record)
	return
end
local tcp = pack(">I2 I2 I4 I4 B B I2 I2 I2", 0, port, 0, 0, words << 4, flags, WINDOW, 0, 0)
local ip = pack(">B B I2 I2 I2 B B I2", VERSION_IHL, 0, IPHDR + #tcp + #record, 0, 0, TTL, protocol, 0) ..
	rep("\0", ADDRESSES)
io.write(rep("\xff", HWADDR) .. rep("\0", HWADDR) .. pack(">I2", ethertype) .. ip .. tcp .. record)
LUA
}

# injected <name> [<bytes>]: the frame forged into <name>, whole or cut to <bytes>, written out of
# the namespace's end, which the host's end receives
injected() {
	local frame="$LUAEBPF_WORK/$1"
	head -c "${2:-$(stat -c %s "$frame")}" "$frame" > "$LUAEBPF_WORK/frame"
	ip netns exec "$NETNS" socat -u "OPEN:$LUAEBPF_WORK/frame" "INTERFACE:$LUAEBPF_PEER"
}

# controlled <n>: the frame naming CONTROL, which passes every test, written and logged for the
# <n>th time, so the frames written before it were read
controlled() {
	injected control
	awaited dmesg_reaches "filter_sni: $CONTROL PASS" "$1"
}

ended() {
	! kill -0 "$listener" 2>/dev/null
}

# delivered <host>: how many bytes a listener on the host's end received of a ClientHello naming
# <host> sent from the namespace, stopped once the sender has gone, as one whose segment was dropped
# never ends, or nothing where it accepted no connection
delivered() {
	rm -f "$LUAEBPF_WORK/received"
	forged "$1" > "$LUAEBPF_WORK/hello"
	socat -u "TCP-LISTEN:$PORT,bind=$HOST,reuseaddr" "CREATE:$LUAEBPF_WORK/received" &
	listener=$!
	awaited listens -t "$PORT"
	ip netns exec "$NETNS" timeout 5 socat -u "OPEN:$LUAEBPF_WORK/hello" "TCP:$HOST:$PORT" 2>/dev/null
	awaited ended
	kill "$listener" 2>/dev/null
	wait "$listener" 2>/dev/null
	stat -c %s "$LUAEBPF_WORK/received" 2>/dev/null
}

trap teardown EXIT
teardown

luaebpf_start 5 luaxdp
[ -r "$OBJECT" ] || skip_script "luaebpf: $OBJECT is not installed; run make install on a kernel with BTF"
command -v socat > /dev/null || skip_script "luaebpf: socat is not installed"

ip netns add "$NETNS"
# a fixed address: a random one is one a host process may replace once the namespace learned it
ip link add "$LUAEBPF_DEV" address "$MAC" type veth peer name "$LUAEBPF_PEER"
ip link set "$LUAEBPF_PEER" netns "$NETNS"
ip addr add "$HOST/24" dev "$LUAEBPF_DEV"
ip link set "$LUAEBPF_DEV" up
ip netns exec "$NETNS" ip addr add "$TARGET/24" dev "$LUAEBPF_PEER"
ip netns exec "$NETNS" ip link set "$LUAEBPF_PEER" up

forged "$CONTROL" "$IPV4" "$TCP" "$PORT" "$PSHACK" "$WORDS" > "$LUAEBPF_WORK/control"
forged ethertype.example "$IPV6" "$TCP" "$PORT" "$PSHACK" "$WORDS" > "$LUAEBPF_WORK/ethertype"
forged protocol.example "$IPV4" "$UDP" "$PORT" "$PSHACK" "$WORDS" > "$LUAEBPF_WORK/protocol"
forged port.example "$IPV4" "$TCP" $((PORT + 1)) "$PSHACK" "$WORDS" > "$LUAEBPF_WORK/port"
forged push.example "$IPV4" "$TCP" "$PORT" "$ACK" "$WORDS" > "$LUAEBPF_WORK/push"
forged long.example "$IPV4" "$TCP" "$PORT" "$PSHACK" "$LONGEST" > "$LUAEBPF_WORK/long"

mark_dmesg
output=$(lunatik run --context=softirq --percpu --dev="$LUAEBPF_DEV" "$SCRIPT" 2>&1)
[ $? -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: $SCRIPT did not run"; }

controlled 1
for name in ethertype protocol port push; do
	injected "$name"
done
controlled 2
logged=$(dmesg_since | grep -cF "filter_sni: $CONTROL PASS")
called=$(dmesg_since | grep -E "filter_sni: (ethertype|protocol|port|push)\.example")

injected control "$ETHER"
injected control $((ETHER + IPHDR))
injected long $((ETHER + IPHDR + TCPHDR))
injected control $((ETHER + IPHDR + TCPHDR))
controlled 3
short=$(dmesg_since)
stops=$(lunatik bpf --errors "$SCRIPT" 2>&1)

if listens -t "$PORT"; then
	held=yes
else
	allowed=$(delivered "$ALLOWED")
	sent=$(stat -c %s "$LUAEBPF_WORK/hello")
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

if [ "$logged" -ne 2 ]; then
	ktap_fail "$TITLE_SKIP: the frame that passes every test was logged $logged times, not twice"
elif [ -n "$called" ]; then
	comment "$called"
	ktap_fail "$TITLE_SKIP"
else
	ktap_pass "$TITLE_SKIP"
fi

raised=$(grep -E "$KTAP_ERRORS" <<< "$short")
if [ -n "$stops" ]; then
	comment "$stops"
	ktap_fail "$TITLE_SHORT: the program stopped"
elif [ -n "$raised" ]; then
	comment "$raised"
	ktap_fail "$TITLE_SHORT: the script was handed one"
elif [ "$(grep -cF "filter_sni: $CONTROL PASS" <<< "$short")" -ne 3 ]; then
	ktap_fail "$TITLE_SHORT: the frame written after them was not logged"
else
	ktap_pass "$TITLE_SHORT"
fi

if [ -n "$held" ]; then
	ktap_skip "$TITLE_PASS: something listens on port $PORT"
	ktap_skip "$TITLE_DROP: something listens on port $PORT"
else
	if [ "$allowed" != "$sent" ]; then
		ktap_fail "$TITLE_PASS: the listener received '${allowed:-no connection}' of the $sent bytes sent"
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

