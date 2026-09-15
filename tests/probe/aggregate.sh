#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A target another kprobe already holds is aggregated by the kernel, and every
# handler attached to that address runs on a hit. One plain hardirq runtime
# registers two probes on the personality syscall, which nothing else on an idle
# host calls, and one setarch calls it exactly once: the second probe.new
# succeeds, both handlers print once, the kprobe list grows by two lines over one
# more address, since an aggregate lists each member separately with the same
# address, and the stop gives all of it back.
#
# The target is the same address twice, not two names the kernel resolves to one:
# that collision is arm64-specific and needs a call to a syscall the kernel does
# not implement, while the same address goes through get_kprobe and
# register_aggr_kprobe on every architecture. The plain path is where this is
# structural, and it is why the test runs there: a percpu set refuses a repeat
# instead, which percpu_probe.sh holds.
#
# Usage: sudo bash tests/probe/aggregate.sh

SCRIPT="tests/probe/aggregate"
KPROBES="/sys/kernel/debug/kprobes/list"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

# how many kprobes the kernel holds; nothing where debugfs does not say
kprobes()
{
	[ -r "$KPROBES" ] && grep -c "" "$KPROBES"
}

# how many addresses they sit on, the first column of each line
addresses()
{
	[ -r "$KPROBES" ] && awk '{print $1}' "$KPROBES" | sort -u | grep -c ""
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

command -v setarch > /dev/null 2>&1 || {
	echo "# SKIP: setarch not available"
	ktap_skip "a second probe on one address is aggregated, and one call runs both handlers"
	ktap_totals
	exit 0
}

mark_dmesg
idle=$(kprobes)
idle_addresses=$(addresses)
run_script "$SCRIPT" hardirq
armed=$(kprobes)
armed_addresses=$(addresses)
setarch "$(uname -m)" -R true > /dev/null 2>&1
sleep 1
lunatik stop "$SCRIPT" > /dev/null 2>&1
stopped=$(kprobes)
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -qF "couldn't find probe table" && fail "a kprobe fired on a runtime that did not register it"
first=$(dmesg_since | grep -cF "probe aggregate: first")
second=$(dmesg_since | grep -cF "probe aggregate: second")
[ "$first" = "1" ] || fail "the first handler ran $first times on one call"
[ "$second" = "1" ] || fail "the second handler ran $second times on one call"
if [ -n "$idle" ]; then
	[ "$armed" = "$((idle + 2))" ] || fail "two probes on one address armed $((armed - idle)) kprobes"
	[ "$armed_addresses" = "$((idle_addresses + 1))" ] || \
		fail "they armed $((armed_addresses - idle_addresses)) addresses instead of one"
	[ "$stopped" = "$idle" ] || fail "stopping the script left $((stopped - idle)) kprobes armed"
fi
ktap_pass "a second probe on one address is aggregated, and one call runs both handlers"

ktap_totals

