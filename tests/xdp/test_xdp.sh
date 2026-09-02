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
ktap_plan 7

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "xdp pass: verdict enforced, packet and argument content verified"
	ktap_skip "xdp drop: verdict enforced correctly"
	ktap_skip "xdp detach: callback stops firing and traffic resumes"
	ktap_skip "xdp attach: refuses a sleepable runtime"
	ktap_skip "xdp zero-key: a zero-sized key is rejected without a crash"
	ktap_skip "xdp process: a process-context runtime under the key is not dispatched"
	ktap_skip "xdp percpu: the callback runs on the instance of the receiving CPU"
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
	rm -f "${PIN}_pass" "${PIN}_drop" "${PIN}_detach" "${PIN}_zerokey" "${PIN}_process" "${PIN}_percpu"
	lunatik stop tests/xdp/pass > /dev/null 2>&1
	lunatik stop tests/xdp/drop > /dev/null 2>&1
	lunatik stop tests/xdp/detach > /dev/null 2>&1
	lunatik stop tests/xdp/attach_sleepable > /dev/null 2>&1
	lunatik stop tests/xdp/process > /dev/null 2>&1
	lunatik stop tests/xdp/percpu > /dev/null 2>&1
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

detach_case()
{
	bpftool prog load "$DIR/xdp_detach.bpf.o" "${PIN}_detach" type xdp ||
		{ ktap_fail "xdp detach: failed to load XDP program"; return 1; }
	bpftool net attach xdp pinned "${PIN}_detach" dev "$IFACE" ||
		{ ktap_fail "xdp detach: failed to attach XDP program"; bpftool prog unpin "${PIN}_detach"; return 1; }

	mark_dmesg
	run_script "tests/xdp/detach" softirq
	check_dmesg || { ktap_fail "xdp detach: script raised an error"; return 1; }

	ip netns exec "$NETNS" ping -c 1 -W 2 "$TARGET" > /dev/null 2>&1 &&
		{ ktap_fail "xdp detach: the first ping should have been dropped"; return 1; }
	ip netns exec "$NETNS" ping -c 1 -W 2 "$TARGET" > /dev/null 2>&1 ||
		{ ktap_fail "xdp detach: traffic did not resume after detach"; return 1; }

	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "${PIN}_detach"
	lunatik stop tests/xdp/detach > /dev/null 2>&1

	dmesg_since | grep -qF "xdp detach test pass" || { ktap_fail "xdp detach: callback did not run"; return 1; }
	ktap_pass "xdp detach: callback stops firing and traffic resumes"
}

zerokey_case()
{
	bpftool prog load "$DIR/xdp_zerokey.bpf.o" "${PIN}_zerokey" type xdp ||
		{ ktap_fail "xdp zero-key: failed to load XDP program"; return 1; }
	bpftool net attach xdp pinned "${PIN}_zerokey" dev "$IFACE" ||
		{ ktap_fail "xdp zero-key: failed to attach XDP program"; bpftool prog unpin "${PIN}_zerokey"; return 1; }

	mark_dmesg
	ip netns exec "$NETNS" ping -c 1 -W 2 "$TARGET" > /dev/null 2>&1
	local reached=$?

	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "${PIN}_zerokey"

	# the program drops on rejection, so a working guard blocks the ping: reachable means
	# the kfunc was never exercised, a clean dmesg alone would be a false pass
	check_dmesg || { ktap_fail "xdp zero-key: the kfunc crashed on a zero-sized key"; return 1; }
	[ "$reached" -ne 0 ] || { ktap_fail "xdp zero-key: ping passed, the kfunc did not run"; return 1; }
	ktap_pass "xdp zero-key: a zero-sized key is rejected without a crash"
}

process_case()
{
	bpftool prog load "$DIR/xdp_process.bpf.o" "${PIN}_process" type xdp ||
		{ ktap_fail "xdp process: failed to load XDP program"; return 1; }
	bpftool net attach xdp pinned "${PIN}_process" dev "$IFACE" ||
		{ ktap_fail "xdp process: failed to attach XDP program"; bpftool prog unpin "${PIN}_process"; return 1; }

	mark_dmesg
	run_script "tests/xdp/process"
	ip netns exec "$NETNS" ping -c 1 -W 2 "$TARGET" > /dev/null 2>&1

	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "${PIN}_process"
	lunatik stop tests/xdp/process > /dev/null 2>&1

	# the kfunc must refuse the runtime before taking its lock: reaching the handler
	# would take a mutex in softirq, which the missing-callback log betrays
	dmesg_since | grep -qF "no callback attached" && { ktap_fail "xdp process: the runtime was dispatched"; return 1; }
	dmesg_since | grep -qF "process-context runtime" || { ktap_fail "xdp process: the kfunc did not refuse the runtime"; return 1; }
	ktap_pass "xdp process: a process-context runtime under the key is not dispatched"
}

# the veth runs the receive softirq on the sending CPU, so the pinned ping picks the instance
percpu_case()
{
	local title="xdp percpu: the callback runs on the instance of the receiving CPU"
	local cpu hits
	cpu=$(sed 's/.*[-,]//' /sys/devices/system/cpu/online)
	[ "$cpu" -ge 1 ] || { ktap_skip "$title (needs >1 CPU)"; return 0; }
	command -v taskset > /dev/null 2>&1 || { ktap_skip "$title (taskset not available)"; return 0; }

	bpftool prog load "$DIR/xdp_percpu.bpf.o" "${PIN}_percpu" type xdp ||
		{ ktap_fail "xdp percpu: failed to load XDP program"; return 1; }
	bpftool net attach xdp pinned "${PIN}_percpu" dev "$IFACE" ||
		{ ktap_fail "xdp percpu: failed to attach XDP program"; bpftool prog unpin "${PIN}_percpu"; return 1; }

	mark_dmesg
	run_script "tests/xdp/percpu" softirq percpu
	check_dmesg || { ktap_fail "xdp percpu: script raised an error"; return 1; }
	taskset -c "$cpu" ip netns exec "$NETNS" ping -c 3 -W 2 "$TARGET" > /dev/null 2>&1

	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "${PIN}_percpu"
	lunatik stop tests/xdp/percpu > /dev/null 2>&1

	hits=$(dmesg_since | grep -o "xdp percpu test hit: cpu [0-9]*" | sort -u)
	[ -n "$hits" ] || { ktap_fail "xdp percpu: the callback did not run"; return 1; }
	[ "$hits" = "xdp percpu test hit: cpu $cpu" ] ||
		{ ktap_fail "xdp percpu: expected the instance of CPU $cpu, got: $(echo $hits)"; return 1; }
	ktap_pass "$title"
}

run_case xdp_pass.bpf.o "${PIN}_pass" pass.lua yes "xdp pass" \
	"xdp pass: verdict enforced, packet and argument content verified" softirq
run_case xdp_drop.bpf.o "${PIN}_drop" drop.lua no "xdp drop" \
	"xdp drop: verdict enforced correctly" softirq percpu
detach_case

mark_dmesg
run_script "tests/xdp/attach_sleepable"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop tests/xdp/attach_sleepable > /dev/null 2>&1
ktap_pass "xdp attach: refuses a sleepable runtime"

zerokey_case
process_case
percpu_case

ktap_totals

