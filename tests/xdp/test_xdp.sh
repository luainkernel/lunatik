#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the XDP dispatch path by loading an XDP program with bpftool and
# attaching it to a veth pair whose peer sits in a network namespace, so a
# ping from the namespace traverses the hook regardless of the host setup.
#
# Usage: sudo bash tests/xdp/test_xdp.sh

MODULE="luaxdp"
IFACE="lunatik0"
PEER="lunatik1"
NETNS="lunatik_xdp"
PIN="/sys/fs/bpf/xdp"
TARGET="10.199.0.1"

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

ktap_header
ktap_plan 2

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "xdp pass: verdict enforced, packet and argument content verified"
	ktap_skip "xdp drop: verdict enforced correctly"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
[ -f /sys/kernel/btf/$MODULE ] || skip_all "$MODULE built without BTF (make btf_install, rebuild)"
command -v bpftool > /dev/null 2>&1 || skip_all "bpftool not available"
command -v clang > /dev/null 2>&1 || skip_all "clang not available"

cleanup()
{
	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "${PIN}_pass" "${PIN}_drop"
	lunatik stop tests/xdp/pass > /dev/null 2>&1
	lunatik stop tests/xdp/drop > /dev/null 2>&1
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$IFACE" 2>/dev/null
}

trap cleanup EXIT
cleanup

make -C "$DIR" || { ktap_fail "failed to build XDP program"; ktap_totals; exit 1; }

ip netns add "$NETNS"
ip link add "$IFACE" type veth peer name "$PEER"
ip link set "$PEER" netns "$NETNS"
ip addr add "$TARGET/24" dev "$IFACE"
ip link set "$IFACE" up
ip netns exec "$NETNS" ip addr add 10.199.0.2/24 dev "$PEER"
ip netns exec "$NETNS" ip link set "$PEER" up

# pin the neighbor entries so ARP never competes with ICMP for the verdict
MAC=$(cat /sys/class/net/$IFACE/address)
PEER_MAC=$(ip netns exec "$NETNS" cat /sys/class/net/$PEER/address)
ip neigh replace 10.199.0.2 lladdr "$PEER_MAC" dev "$IFACE" nud permanent
ip netns exec "$NETNS" ip neigh replace "$TARGET" lladdr "$MAC" dev "$PEER" nud permanent

run_case()
{
	local obj="$1" pin="$2" script="$3" expect_reachable="$4" label="$5" title="$6"
	shift 6

	bpftool prog load "$DIR/$obj" "$pin" type xdp ||
		{ ktap_fail "$label: failed to load XDP program"; return 1; }
	bpftool net attach xdp pinned "$pin" dev "$IFACE" ||
		{ ktap_fail "$label: failed to attach XDP program"; bpftool prog unpin "$pin"; return 1; }

	mark_dmesg
	run_script "tests/xdp/$script" "$@"
	check_dmesg || { ktap_fail "$label: script raised an error"; return 1; }

	ip netns exec "$NETNS" ping -c 1 -W 2 "$TARGET" > /dev/null 2>&1
	local reached=$?

	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "$pin"
	lunatik stop "tests/xdp/${script%.lua}" > /dev/null 2>&1

	dmesg_since | grep -qF "$label test fail" && { ktap_fail "$label: callback reported a failure"; return 1; }
	dmesg_since | grep -qF "$label test pass" || { ktap_fail "$label: verdict callback did not run"; return 1; }

	if [ "$expect_reachable" = "yes" ] && [ "$reached" -ne 0 ]; then
		ktap_fail "$label: expected PASS but ping was blocked"; return 1
	fi
	if [ "$expect_reachable" = "no" ] && [ "$reached" -eq 0 ]; then
		ktap_fail "$label: expected DROP but ping got through"; return 1
	fi

	ktap_pass "$title"
}

run_case xdp_pass.bpf.o "${PIN}_pass" pass.lua yes "xdp pass" \
	"xdp pass: verdict enforced, packet and argument content verified" softirq
run_case xdp_drop.bpf.o "${PIN}_drop" drop.lua no "xdp drop" \
	"xdp drop: verdict enforced correctly" softirq percpu

ktap_totals

