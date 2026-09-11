#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for a netfilter hook in a percpu script: the runtimes share one
# LOCAL_IN hook, so each marked ping request is handled exactly once, and by the
# runtime of the CPU that received it, which is where the loopback delivers the
# pinned ping; a marked packet reaching that hook while the runtimes are still
# being created finds none published on its CPU, and is accepted without being
# counted; one set holds a hook per target, and a second registration of the
# same one in a runtime is refused; a registration from a callback, after the
# script loaded, is refused before it could sleep in softirq; and the same
# script registers as a plain softirq runtime. The exactly-once assertion runs
# on the shared hook, where it is structural. The burst starts when the script
# reports the hook armed, and runs inside the spin every runtime does before
# returning, so it arrives while no runtime is published.
#
# Usage: sudo bash tests/runtime/percpu_netfilter.sh

SCRIPT="tests/runtime/percpu_netfilter"
CHECK="tests/runtime/percpu_netfilter_check"
TWICE="tests/runtime/percpu_netfilter_twice"
LATE="tests/runtime/percpu_netfilter_late"
EARLY="tests/runtime/percpu_netfilter_early"
ARMED="percpu netfilter early: armed"
TARGETS="percpu netfilter twice: two targets armed"
MODULE="luanetfilter"
MARK=208
COUNT=5
BURST=10
TRIES=100

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CHECK" > /dev/null 2>&1
	lunatik stop "$TWICE" > /dev/null 2>&1
	lunatik stop "$LATE" > /dev/null 2>&1
	lunatik stop "$EARLY" > /dev/null 2>&1
}

burst_when_armed()
{
	local try
	for ((try = 0; try < TRIES; try++)); do
		dmesg_since | grep -qF "$ARMED" && break
		sleep 0.02
	done
	ping -f -c $BURST -m $MARK 127.0.0.1 > /dev/null 2>&1
}

count_pinned()
{
	local cpu="$1"
	mark_dmesg
	taskset -c "$cpu" ping -c $COUNT -i 0.2 -m $MARK 127.0.0.1 > /dev/null 2>&1
	dmesg_since | grep -qF "couldn't find hook" && fail "a hook fired for a runtime that did not register it"
	run_script "$CHECK"
	check_dmesg || { ktap_totals; exit 1; }
	lunatik stop "$CHECK" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_skip "the runtimes share one hook: each marked request is counted once, by the receiving CPU"
	ktap_skip "a packet reaching the shared hook before the runtimes are published is accepted, uncounted"
	ktap_skip "one set holds a hook per target; a second registration of the same one is refused"
	ktap_skip "a registration from a callback, after load, is refused"
	ktap_skip "the same script registers as a plain softirq runtime"
	ktap_totals
	exit 0
}

cpu=$(sed 's/.*[-,]//' /sys/devices/system/cpu/online)
run_script "$SCRIPT" softirq percpu
count_pinned "$cpu"
dmesg_since | grep -qF "percpu netfilter: nf_percpu:$cpu $COUNT" || \
	fail "the packets were not counted by the runtime of CPU $cpu: $(dmesg_since | grep 'percpu netfilter')"
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "the runtimes share one hook: each marked request is counted once, by the receiving CPU"

mark_dmesg
burst_when_armed &
burst=$!
run_script "$EARLY" softirq percpu
wait $burst || fail "a marked ping was lost while the runtimes were being created"
count_pinned "$cpu"
dmesg_since | grep -qF "percpu netfilter: nf_percpu:$cpu $COUNT" || \
	fail "the burst was counted, or it missed the runtime of CPU $cpu: $(dmesg_since | grep 'percpu netfilter')"
lunatik stop "$EARLY" > /dev/null 2>&1
ktap_pass "a packet reaching the shared hook before the runtimes are published is accepted, uncounted"

mark_dmesg
output=$(lunatik run "$TWICE" softirq percpu 2>&1)
echo "$output" | grep -q "hook already registered" || fail "the second registration was not refused: $output"
dmesg_since | grep -qF "$TARGETS" || fail "the hook on a second target was taken for the one already in the set"
listed=$(lunatik list)
case "$listed" in
	*"$TWICE"*) fail "the refused run left the script registered: $listed" ;;
esac
ktap_pass "one set holds a hook per target; a second registration of the same one is refused"

mark_dmesg
run_script "$LATE" softirq percpu
taskset -c "$cpu" ping -c 1 -m $MARK 127.0.0.1 > /dev/null 2>&1
lunatik stop "$LATE" > /dev/null 2>&1
dmesg_since | grep -qF "percpu netfilter late: " || fail "the callback did not run"
dmesg_since | grep -q "percpu netfilter late: .*not allowed after module load" || \
	fail "the late registration was not refused: $(dmesg_since | grep 'percpu netfilter late')"
ktap_pass "a registration from a callback, after load, is refused"

run_script "$SCRIPT" softirq
count_pinned "$cpu"
dmesg_since | grep -qF "percpu netfilter: nf_percpu:plain $COUNT" || \
	fail "the plain runtime did not count the packets: $(dmesg_since | grep 'percpu netfilter')"
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "the same script registers as a plain softirq runtime"

ktap_totals

