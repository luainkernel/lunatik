#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for a kprobe in a percpu script: the runtimes share one
# kprobe on the personality syscall, so a pinned setarch, which calls it once,
# is handled exactly once and by the runtime of the CPU it ran on, which for a
# kprobe is where the syscall executed, with no runtime reached through a kprobe
# it did not register; a call reaching the shared kprobe while the runtimes are
# still being created, pinned to the CPU whose runtime is published last, is
# dropped, and the same call is counted once they are up; a second probe on the
# same symbol in one runtime is refused; stop and enable are refused in a percpu
# runtime, where the object owns the kprobe; the same script probes as a plain
# hardirq runtime; and a plain runtime stops its own probe, twice with no
# effect, is refused an enable afterwards, and refuses a probe on a symbol the
# kernel does not have, releasing the runtime that probe took.
#
# Usage: sudo bash tests/probe/percpu_probe.sh

SCRIPT="tests/probe/percpu_probe"
TWICE="tests/probe/percpu_probe_twice"
STOP="tests/probe/percpu_probe_stop"
PLAIN="tests/probe/percpu_probe_plain"
EARLY="tests/probe/percpu_probe_early"
ARMED="percpu probe early: armed"
COUNT=3
TRIES=100

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$TWICE" > /dev/null 2>&1
	lunatik stop "$STOP" > /dev/null 2>&1
	lunatik stop "$PLAIN" > /dev/null 2>&1
	lunatik stop "$EARLY" > /dev/null 2>&1
}

trigger()
{
	local cpu="$1" i
	for ((i = 0; i < COUNT; i++)); do
		taskset -c "$cpu" setarch "$(uname -m)" -R true > /dev/null 2>&1
	done
}

trigger_when_armed()
{
	local try
	for ((try = 0; try < TRIES; try++)); do
		dmesg_since | grep -qF "$ARMED" && break
		sleep 0.02
	done
	trigger "$1"
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

command -v taskset > /dev/null 2>&1 && command -v setarch > /dev/null 2>&1 || {
	echo "# SKIP: taskset or setarch not available"
	ktap_skip "the runtimes share one kprobe: each call is handled once, by the runtime of the CPU it ran on"
	ktap_skip "a call reaching the shared kprobe before the runtimes are published is dropped"
	ktap_skip "a second probe on the same symbol in one runtime is refused"
	ktap_skip "stop and enable are refused in a percpu runtime"
	ktap_skip "the same script probes as a plain hardirq runtime"
	ktap_skip "a plain runtime stops its probe once, refuses enable afterwards and refuses an unknown symbol"
	ktap_totals
	exit 0
}

cpu=$(sed 's/.*[-,]//' /sys/devices/system/cpu/online)

mark_dmesg
run_script "$SCRIPT" hardirq percpu
trigger "$cpu"
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -qF "couldn't find probe table" && fail "a kprobe fired on a runtime that did not register it"
hits=$(dmesg_since | grep -c "percpu probe: cpu $cpu$")
others=$(dmesg_since | grep -o "percpu probe: cpu [0-9]*" | grep -vc "cpu $cpu$")
lunatik stop "$SCRIPT" > /dev/null 2>&1
[ "$hits" = "$COUNT" ] || fail "the runtime of CPU $cpu counted $hits of $COUNT"
[ "$others" = "0" ] || fail "$others hits landed on another runtime: $(dmesg_since | grep -o 'percpu probe: cpu [0-9]*' | sort -u | tr '\n' ' ')"
ktap_pass "the runtimes share one kprobe: each call is handled once, by the runtime of the CPU it ran on"

mark_dmesg
trigger_when_armed "$cpu" &
early=$!
run_script "$EARLY" hardirq percpu
wait $early
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -qF "couldn't find probe table" && fail "a kprobe fired for a runtime that did not register it"
early_hits=$(dmesg_since | grep -c "percpu probe early: cpu")
trigger "$cpu"
late_hits=$(dmesg_since | grep -c "percpu probe early: cpu $cpu\$")
lunatik stop "$EARLY" > /dev/null 2>&1
[ "$early_hits" = "0" ] || fail "$early_hits calls were handled before the runtimes were published"
[ "$late_hits" = "$COUNT" ] || fail "the same trigger counted $late_hits of $COUNT once the runtimes were published"
ktap_pass "a call reaching the shared kprobe before the runtimes are published is dropped"

output=$(lunatik run "$TWICE" hardirq percpu 2>&1)
echo "$output" | grep -q "probe already registered" || fail "the second registration was not refused: $output"
listed=$(lunatik list)
case "$listed" in
	*"$TWICE"*) fail "the refused run left the script registered: $listed" ;;
esac
ktap_pass "a second probe on the same symbol in one runtime is refused"

mark_dmesg
run_script "$STOP" hardirq percpu
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$STOP" > /dev/null 2>&1
ktap_pass "stop and enable are refused in a percpu runtime"

mark_dmesg
run_script "$SCRIPT" hardirq
trigger "$cpu"
check_dmesg || { ktap_totals; exit 1; }
plain=$(dmesg_since | grep -c "percpu probe: cpu plain$")
lunatik stop "$SCRIPT" > /dev/null 2>&1
[ "$plain" = "$COUNT" ] || fail "the plain runtime counted $plain of $COUNT"
ktap_pass "the same script probes as a plain hardirq runtime"

mark_dmesg
run_script "$PLAIN" hardirq
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$PLAIN" > /dev/null 2>&1
ktap_pass "a plain runtime stops its probe once, refuses enable afterwards and refuses an unknown symbol"

ktap_totals

