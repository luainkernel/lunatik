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
# The non-linear case sends a TCP segment from the host to a listener in the
# namespace instead: tcp_sendmsg keeps the payload in page fragments, so the skb
# the classifier sees is non-linear. The program hands it to bpf_luatc_run, where
# skb:data(), copy() and resize() raise "skb is not linear", then pulls it with
# bpf_skb_pull_data and hands it again, where the callback reads, copies and
# shrinks the whole packet and drops it; TCP sends it again. The sender's
# SO_PRIORITY picks the segment, a value outside 0..6, which only a process with
# CAP_NET_ADMIN or CAP_NET_RAW may set. The case skips without socat.
#
# The reattach script also runs without a program, with a kprobe on luadata_release
# counting the data objects freed: its body attaches twice and collects twice, and
# the context the second attach replaces frees its skb's three views and its argument,
# four data objects; a build whose skb leaves its views registered frees one. The
# case skips where the kprobe cannot be placed.
#
# The verdict cases send one ping each, whose payload size picks what the callback
# of verdict.lua answers to the echo reply: nothing, a value that is not a number, an
# action as a string, a number past the TC actions, one below them, one whose low 32
# bits are SHOT, or a raise. Each makes bpf_luatc_run return -1, on which the program
# lets the reply out and returns anything else as it came, so a value the kfunc let
# through reaches the kernel; the five that are not an action log "invalid action",
# which no other case logs, and each case reads back the line its callback printed.
#
# Usage: sudo bash tests/tc/test_tc.sh

MODULE="luatc"
IFACE="lunatik0"
PEER="lunatik1"
NETNS="lunatik_tc"
HOST="10.198.0.1"
TARGET="10.198.0.2"
PIN="/sys/fs/bpf/lunatik_tc"
PORT=5569
PAYLOAD=1024             # PAYLOAD in nonlinear.lua
PRIORITY=$((0x13690000)) # PRIORITY in nonlinear.lua
REFUSED="tc nonlinear: data, copy and resize refuse a non-linear skb"
PULLED="tc nonlinear: a pulled skb is read, copied and resized whole"
REPLACED="tc reattach: the replaced context frees its skb's views and its argument"
FREED="lunatik_tc/luadata_release"
REPLACED_OBJECTS=4 # the replaced context's three views and its argument
PREFIX="tc verdict: "
INVALID="$MODULE: invalid action"
RAISED="${PREFIX}raised"

# the verdict cases: the payload sizes verdict.lua reads, the case each picks, what it logs
VERDICT_PAYLOADS=(101 102 103 104 105 106 107)
VERDICT_CASES=(none boolean string range wrap raise below)
VERDICT_LOGS=("" "$INVALID" "$INVALID" "$INVALID" "$INVALID" "$RAISED" "$INVALID")
VERDICT_TITLES=(
	"tc verdict: a callback that returns nothing leaves the verdict to the program"
	"tc verdict: a value that is not a number is refused and logged"
	"tc verdict: an action as a string is refused and logged"
	"tc verdict: a number past the TC actions is refused and logged"
	"tc verdict: a number whose low 32 bits are SHOT is refused and logged"
	"tc verdict: a callback that raises leaves the verdict to the program"
	"tc verdict: a number below the TC actions is refused and logged"
)

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
ktap_plan 17

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "tc pass: verdict enforced, packet and argument content verified"
	ktap_skip "tc drop: verdict enforced correctly"
	ktap_skip "$REPLACED"
	ktap_skip "tc reattach: re-attach installs the last callback"
	ktap_skip "tc detach: callback stops firing and traffic resumes"
	ktap_skip "tc attach: refuses a sleepable runtime"
	ktap_skip "tc zero-key: a zero-sized key is rejected without a crash"
	ktap_skip "tc data: \"net\" starts at the IP header, and the views end at the frame's tail"
	ktap_skip "$REFUSED"
	ktap_skip "$PULLED"
	for title in "${VERDICT_TITLES[@]}"; do
		ktap_skip "$title"
	done
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
	lunatik stop tests/tc/reattach > /dev/null 2>&1
	lunatik stop tests/tc/detach > /dev/null 2>&1
	lunatik stop tests/tc/attach_sleepable > /dev/null 2>&1
	lunatik stop tests/tc/data > /dev/null 2>&1
	lunatik stop tests/tc/nonlinear > /dev/null 2>&1
	lunatik stop tests/tc/verdict > /dev/null 2>&1
	pkill -f "TCP-LISTEN:$PORT," 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$IFACE" 2>/dev/null
	kprobe_remove "$FREED"
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
	run_script "$@" "tests/tc/$script"

	# egress from the host toward the namespaced peer is what the classifier sees
	ip netns exec "$NETNS" ping -c 1 -W 2 "$HOST" > /dev/null 2>&1
	local reached=$?

	tc_unload
	lunatik stop "tests/tc/${script%.lua}" > /dev/null 2>&1

	check_dmesg || { ktap_fail "$label: script raised an error"; return 1; }
	dmesg_since | grep -qF "no callback attached" && { ktap_fail "$label: a callback was reported missing"; return 1; }
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
	run_script --context=softirq "tests/tc/detach"

	ip netns exec "$NETNS" ping -c 1 -W 2 "$HOST" > /dev/null 2>&1
	local dropped=$?
	ip netns exec "$NETNS" ping -c 1 -W 2 "$HOST" > /dev/null 2>&1
	local resumed=$?

	tc_unload
	lunatik stop tests/tc/detach > /dev/null 2>&1

	check_dmesg || { ktap_fail "tc detach: script raised an error"; return 1; }
	[ "$dropped" -ne 0 ] || { ktap_fail "tc detach: the first ping should have been dropped"; return 1; }
	[ "$resumed" -eq 0 ] || { ktap_fail "tc detach: traffic did not resume after detach"; return 1; }
	dmesg_since | grep -qF "tc detach test pass" || { ktap_fail "tc detach: callback did not run"; return 1; }
	dmesg_since | grep -qF "no callback attached" || { ktap_fail "tc detach: the kfunc did not report the missing callback"; return 1; }
	ktap_pass "tc detach: callback stops firing and traffic resumes"
}

replaced_case()
{
	local before freed
	kprobe_place "$FREED" luadata_release ||
		{ echo "# SKIP: couldn't place a kprobe on luadata_release"; ktap_skip "$REPLACED"; return 0; }

	before=$(kprobe_hits "$FREED")
	mark_dmesg
	run_script --context=softirq "tests/tc/reattach"
	freed=$(( $(kprobe_hits "$FREED") - before ))

	lunatik stop tests/tc/reattach > /dev/null 2>&1
	kprobe_remove "$FREED"

	check_dmesg || { ktap_fail "$REPLACED: script raised an error"; return 1; }
	[ "$freed" -eq "$REPLACED_OBJECTS" ] || { ktap_fail "$REPLACED: $freed of its $REPLACED_OBJECTS data objects freed"; return 1; }
	ktap_pass "$REPLACED"
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

nonlinear_verdict()
{
	local title="$1" cell lines
	shift
	for cell in "$@"; do
		lines=$(dmesg_since | grep -F "tc nonlinear: $cell ")
		if [ -z "$lines" ] || echo "$lines" | grep -q " FAIL "; then
			ktap_fail "$title"
			comment "${lines:-no $cell report}"
			return 1
		fi
	done
	ktap_pass "$title"
}

nonlinear_case()
{
	if ! command -v socat > /dev/null 2>&1; then
		echo "# SKIP: socat not available"
		ktap_skip "$REFUSED"
		ktap_skip "$PULLED"
		return 0
	fi

	tc_load tc_nonlinear.bpf.o ||
		{ ktap_fail "$REFUSED: failed to load/attach TC program"; ktap_fail "$PULLED"; return 1; }

	mark_dmesg
	run_script --context=softirq "tests/tc/nonlinear"

	ip netns exec "$NETNS" socat -u "TCP-LISTEN:$PORT,reuseaddr" OPEN:/dev/null &
	local listener=$!
	for _ in $(seq 20); do
		ip netns exec "$NETNS" ss -Hltn "sport = :$PORT" | grep -q . && break
		sleep 0.1
	done
	head -c "$PAYLOAD" /dev/zero | timeout 5 socat -u - "TCP:$TARGET:$PORT,priority=$PRIORITY" 2>/dev/null
	for _ in $(seq 20); do
		dmesg_since | grep -qF "tc nonlinear: pulled " && break
		sleep 0.5
	done
	for _ in $(seq 20); do # the listener exits once TCP delivered the dropped segment again
		kill -0 "$listener" 2>/dev/null || break
		sleep 0.5
	done

	tc_unload
	lunatik stop tests/tc/nonlinear > /dev/null 2>&1
	kill "$listener" 2>/dev/null

	check_dmesg || { ktap_fail "$REFUSED"; ktap_fail "$PULLED"; return 1; }
	nonlinear_verdict "$REFUSED" data copy resize
	nonlinear_verdict "$PULLED" pulled
}

verdict_fail()
{
	local title
	for title in "${VERDICT_TITLES[@]}"; do
		ktap_fail "$title: $1"
	done
}

# verdict_check <i> <reached> <log>: the callback of case i ran, the ping passed, and it logged what it should
verdict_check()
{
	local case="${VERDICT_CASES[$1]}" expected="${VERDICT_LOGS[$1]}" title="${VERDICT_TITLES[$1]}"

	grep -qE "${PREFIX}${case}\$" <<< "$3" || { ktap_fail "$title: the callback did not run"; return; }
	grep -qE "$KTAP_ERRORS" <<< "$3" && { ktap_fail "$title: script raised an error"; return; }
	[ "$2" -eq 0 ] || { ktap_fail "$title: the ping was dropped"; return; }
	[ -z "$expected" ] || grep -qF "$expected" <<< "$3" || { ktap_fail "$title: \"$expected\" not logged"; return; }
	[ "$expected" = "$INVALID" ] || ! grep -qF "$INVALID" <<< "$3" || { ktap_fail "$title: logged as invalid"; return; }
	ktap_pass "$title"
}

verdict_case()
{
	local i
	local -a reached logs

	tc_load tc_verdict.bpf.o || { verdict_fail "failed to load/attach TC program"; return 1; }

	mark_dmesg
	run_script --context=softirq "tests/tc/verdict"
	for i in "${!VERDICT_CASES[@]}"; do
		ip netns exec "$NETNS" ping -c 1 -W 2 -s "${VERDICT_PAYLOADS[$i]}" "$HOST" > /dev/null 2>&1
		reached[$i]=$?
		logs[$i]=$(dmesg_since)
		mark_dmesg
	done

	tc_unload
	lunatik stop tests/tc/verdict > /dev/null 2>&1

	for i in "${!VERDICT_CASES[@]}"; do
		verdict_check "$i" "${reached[$i]}" "${logs[$i]}"
	done
}

run_case tc_pass.bpf.o pass.lua yes "tc pass" \
	"tc pass test pass: packet and argument content verified" --context=softirq
run_case tc_drop.bpf.o drop.lua no "tc drop" \
	"tc drop test pass: verdict set to drop" --context=softirq --percpu
replaced_case
run_case tc_reattach.bpf.o reattach.lua yes "tc reattach" \
	"tc reattach test pass: re-attach installed the last callback" --context=softirq
detach_case

mark_dmesg
run_script "tests/tc/attach_sleepable"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop tests/tc/attach_sleepable > /dev/null 2>&1
ktap_pass "tc attach: refuses a sleepable runtime"

zerokey_case

run_case tc_data.bpf.o data.lua yes "tc data" \
	"tc data: \"net\" starts at the IP header, and the views end at the frame's tail" --context=softirq

nonlinear_case
verdict_case

ktap_totals

