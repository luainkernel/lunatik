#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.channel end to end FROM SOFTIRQ: a softirq runtime registers a
# generic netlink family ("lunatiktest"), unicasts to an absent port id (which
# must return false), and installs a PRE_ROUTING netfilter hook that, on
# received traffic (NET_RX softirq), both multicasts to the group and unicasts
# to a fixed port id. A userspace subscriber (built with gcc) binds to that port
# id and joins the group, and receives both messages, proving kernel-to-
# userspace multicast and unicast delivery from softirq. On its first packet the
# hook also calls netlink.channel.new, which registers a family and sleeps, and must
# be refused there; the name is empty so that a build without that refusal raises
# on the name instead of registering a family from softirq. The same script run
# percpu is refused at load, since every runtime would register the one family.
# Its body refuses, as out of bounds, a port id past 32 bits or negative and a
# command past 8 bits or negative, each with low bits a truncating build would
# send to, and takes both at the top of their range; it refuses a unicast to
# port id 0, the kernel's, and a family named with the empty string, with
# GENL_NAMSIZ bytes, which leave no room for the terminator, or with the name it
# registered, which genl_register_family answers with EEXIST, and registers the
# longest name. Once the script stops, neither family it registered is left.
#
# Usage: sudo bash tests/netlink/channel.sh

SCRIPT="tests/netlink/channel"
MODULE="luanetlink"
FAMILY="lunatiktest"
LONGEST="xxxxxxxxxxxxxxx" # GENL_NAMSIZ - 1 bytes
DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

cleanup() {
	kill "$SUB_PID" 2>/dev/null
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -f "$SUB_BIN" "$SUB_OUT" "$SUB_ERR"
}
trap cleanup EXIT
cleanup

SUB_BIN="$(mktemp)"
SUB_OUT="$(mktemp)"
SUB_ERR="$(mktemp)"

ktap_header
ktap_plan 9

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
command -v genl > /dev/null 2>&1 || skip "channel: genl tool unavailable"

build_peer "$DIR/channel_subscriber.c" "$SUB_BIN" || skip "channel: no subscriber, without gcc or failing to build"

output=$(lunatik run --context=softirq --percpu "$SCRIPT" 2>&1)
echo "$output" | grep -q "not allowed in a percpu runtime" || fail "percpu run did not refuse the channel: $output"
genl ctrl get name "$FAMILY" > /dev/null 2>&1 && fail "the refused percpu run left $FAMILY registered"
ktap_pass "channel: a percpu runtime is refused at load"

mark_dmesg
run_script --context=softirq "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "netlink channel: unicast to absent peer returns false" || fail "unicast did not return false"
ktap_pass "channel: unicast to an absent port id returns false"

dmesg_since | grep -q "netlink channel: a port id or command past its range is refused" || fail "a port id or command past its range was not refused"
ktap_pass "channel: a port id or command past its range is refused as out of bounds"

dmesg_since | grep -q "netlink channel: unicast to port id 0 is refused" || fail "a unicast to port id 0 was not refused"
ktap_pass "channel: a unicast to port id 0 is refused"

dmesg_since | grep -q "netlink channel: new refuses an empty, too long or registered name" || fail "netlink.channel.new took a name it should refuse"
ktap_pass "channel: new refuses an empty name, one of GENL_NAMSIZ bytes and a registered one"

# the family is now registered; resolve its multicast group id (the group line
# is the only one with an "ID-0x" token; the family id prints as "ID: 0x")
GRP=$(genl ctrl get name "$FAMILY" 2>/dev/null \
	| grep -oiE 'ID-0x[0-9a-fA-F]+' | head -1 | sed 's/^[Ii][Dd]-//')
[ -n "$GRP" ] || fail "could not resolve multicast group for family $FAMILY"

"$SUB_BIN" "$GRP" > "$SUB_OUT" 2> "$SUB_ERR" &
SUB_PID=$!
ready=""
for _ in $(seq 1 50); do grep -q READY "$SUB_ERR" 2>/dev/null && { ready=1; break; }; sleep 0.1; done
[ -n "$ready" ] || fail "subscriber not ready: $(cat "$SUB_ERR")"

# generate loopback traffic; the received packet fires PRE_ROUTING in NET_RX softirq
for _ in $(seq 1 5); do echo x > /dev/udp/127.0.0.1/9999 2>/dev/null; sleep 0.1; done

wait "$SUB_PID" 2>/dev/null
check_dmesg || { ktap_totals; exit 1; }

grep -q "channel multicast ok" "$SUB_OUT" || fail "subscriber did not receive the softirq multicast"
ktap_pass "channel: userspace received a multicast sent from a softirq hook"

grep -q "channel unicast ok" "$SUB_OUT" || fail "subscriber did not receive the softirq unicast"
ktap_pass "channel: userspace received a unicast sent from a softirq hook"

dmesg_since | grep -q "netlink channel: new from a hook is refused" || fail "netlink.channel.new was not refused from a hook"
ktap_pass "channel: netlink.channel.new from a softirq hook raises"

lunatik stop "$SCRIPT" 2>/dev/null
genl ctrl get name "$FAMILY" > /dev/null 2>&1 && fail "$FAMILY outlived the script's stop"
genl ctrl get name "$LONGEST" > /dev/null 2>&1 && fail "$LONGEST outlived the script's stop"
ktap_pass "channel: a stop unregisters every family the script registered"

ktap_totals

