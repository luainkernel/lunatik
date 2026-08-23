#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the TC dispatch path by loading a TC/eBPF program with `tc` and
# attaching it to the egress of a veth pair whose peer sits in a network
# namespace, so a ping from the namespace traverses the hook regardless
# of the host setup.
#
# Usage: sudo bash tests/tc/test_tc.sh

MODULE="luatc"
IFACE="lunatik0"
PEER="lunatik1"
NETNS="lunatik_tc"
HOST="10.198.0.1"
TARGET="10.198.0.2"
PIN="/sys/fs/bpf/lunatik_tc"

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

# load with bpftool (current libbpf) and attach the pinned program, so the suite
# does not depend on the distribution's iproute2 being new enough to load it
tc_load()
{
	tc qdisc add dev "$IFACE" clsact 2>/dev/null
	bpftool prog load "$DIR/$1" "$PIN" 2>/dev/null &&
		tc filter add dev "$IFACE" egress bpf da object-pinned "$PIN"
}

tc_unload()
{
	tc filter del dev "$IFACE" egress 2>/dev/null
	rm -f "$PIN"
}

ktap_header
ktap_plan 5

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "tc pass: verdict enforced, packet and argument content verified"
	ktap_skip "tc drop: verdict enforced correctly"
	ktap_skip "tc detach: callback stops firing and traffic resumes"
	ktap_skip "tc attach: refuses a sleepable runtime"
	ktap_skip "tc zero-key: a zero-sized key is rejected without a crash"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
[ -f /sys/kernel/btf/$MODULE ] || skip_all "$MODULE built without BTF (make btf_install, rebuild)"
command -v bpftool > /dev/null 2>&1 || skip_all "bpftool not available"
command -v clang > /dev/null 2>&1 || skip_all "clang not available"
command -v tc > /dev/null 2>&1 || skip_all "tc not available"

cleanup()
{
	tc_unload
	tc qdisc del dev "$IFACE" clsact 2>/dev/null
	lunatik stop tests/tc/pass > /dev/null 2>&1
	lunatik stop tests/tc/drop > /dev/null 2>&1
	lunatik stop tests/tc/detach > /dev/null 2>&1
	lunatik stop tests/tc/attach_sleepable > /dev/null 2>&1
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$IFACE" 2>/dev/null
}

trap cleanup EXIT
cleanup

make -C "$DIR" || { ktap_fail "failed to build TC program"; ktap_totals; exit 1; }

ip netns add "$NETNS"
ip link add "$IFACE" type veth peer name "$PEER"
ip link set "$PEER" netns "$NETNS"
ip addr add "$HOST/24" dev "$IFACE"
ip link set "$IFACE" up
ip netns exec "$NETNS" ip addr add "$TARGET"/24 dev "$PEER"
ip netns exec "$NETNS" ip link set "$PEER" up

# pin the neighbor entries so ARP never competes with ICMP for the verdict
MAC=$(cat /sys/class/net/$IFACE/address)
PEER_MAC=$(ip netns exec "$NETNS" cat /sys/class/net/$PEER/address)
ip neigh replace "$TARGET" lladdr "$PEER_MAC" dev "$IFACE" nud permanent
ip netns exec "$NETNS" ip neigh replace "$HOST" lladdr "$MAC" dev "$PEER" nud permanent

run_case()
{
	local obj="$1" script="$2" expect_reachable="$3" label="$4" title="$5"
	shift 5

	tc_load "$obj" ||
		{ ktap_fail "$label: failed to load/attach TC program"; return 1; }

	mark_dmesg
	run_script "tests/tc/$script" "$@"
	check_dmesg || { ktap_fail "$label: script raised an error"; return 1; }

	# egress from the host toward the namespaced peer is what the classifier sees
	ip netns exec "$NETNS" ping -c 1 -W 2 "$HOST" > /dev/null 2>&1
	local reached=$?

	tc_unload
	lunatik stop "tests/tc/${script%.lua}" > /dev/null 2>&1

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

detach_case()
{
	tc_load tc_detach.bpf.o ||
		{ ktap_fail "tc detach: failed to load/attach TC program"; return 1; }

	mark_dmesg
	run_script "tests/tc/detach" softirq
	check_dmesg || { ktap_fail "tc detach: script raised an error"; return 1; }

	ip netns exec "$NETNS" ping -c 1 -W 2 "$HOST" > /dev/null 2>&1 &&
		{ ktap_fail "tc detach: the first ping should have been dropped"; return 1; }
	ip netns exec "$NETNS" ping -c 1 -W 2 "$HOST" > /dev/null 2>&1 ||
		{ ktap_fail "tc detach: traffic did not resume after detach"; return 1; }

	tc_unload
	lunatik stop tests/tc/detach > /dev/null 2>&1

	dmesg_since | grep -qF "tc detach test pass" || { ktap_fail "tc detach: callback did not run"; return 1; }
	ktap_pass "tc detach: callback stops firing and traffic resumes"
}

zerokey_case()
{
	tc_load tc_zerokey.bpf.o ||
		{ ktap_fail "tc zero-key: failed to load/attach TC program"; return 1; }

	mark_dmesg
	ip netns exec "$NETNS" ping -c 1 -W 2 "$HOST" > /dev/null 2>&1
	local reached=$?

	tc_unload

	# the program drops on rejection, so a working guard blocks the ping: reachable means
	# the kfunc was never exercised, a clean dmesg alone would be a false pass
	check_dmesg || { ktap_fail "tc zero-key: the kfunc crashed on a zero-sized key"; return 1; }
	[ "$reached" -ne 0 ] || { ktap_fail "tc zero-key: ping passed, the kfunc did not run"; return 1; }
	ktap_pass "tc zero-key: a zero-sized key is rejected without a crash"
}

run_case tc_pass.bpf.o pass.lua yes "tc pass" \
	"tc pass test pass: packet content verified" softirq
run_case tc_drop.bpf.o drop.lua no "tc drop" \
	"tc drop test pass: verdict set to drop" softirq percpu
detach_case

mark_dmesg
run_script "tests/tc/attach_sleepable"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop tests/tc/attach_sleepable > /dev/null 2>&1
ktap_pass "tc attach: refuses a sleepable runtime"

zerokey_case

ktap_totals

