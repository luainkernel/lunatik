#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the sched tests and reports aggregated KTAP results.
#
# Covers the attach guards, which need no sched_ext program: a sleepable
# runtime is refused, and a hardirq runtime attaches, re-attaches and detaches
# without error. Skipped when the kernel has no sched_ext, whose kset is
# /sys/kernel/sched_ext.
#
# Usage: sudo bash tests/sched/run.sh

SLEEPABLE="tests/sched/attach_sleepable"
REATTACH="tests/sched/reattach"

PASS="tests/sched/pass"
BPF_OBJ="tests/sched/sched_pass.bpf.o"
PIN="/sys/fs/bpf/luasched"


DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

ktap_header
ktap_plan 3

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "sched attach: refuses a sleepable runtime"
	ktap_skip "sched reattach: a hardirq runtime attaches, re-attaches and detaches"
	ktap_totals
	exit 0
}

[ -d /sys/kernel/sched_ext ] || skip_all "kernel without sched_ext"

cleanup()
{
	lunatik stop "$SLEEPABLE" 2>/dev/null
	lunatik stop "$REATTACH" 2>/dev/null
	sudo bpftool struct_ops unregister name luasched_ops 2>/dev/null
	rm -f "$PIN"
	lunatik stop "$PASS" 2>/dev/null
}
trap cleanup EXIT
cleanup

if run_test "$SLEEPABLE"; then
	ktap_pass "sched attach: refuses a sleepable runtime"
else
	ktap_fail "sched attach: refuses a sleepable runtime"
fi

if run_test "$REATTACH" hardirq; then
	ktap_pass "sched reattach: a hardirq runtime attaches, re-attaches and detaches"
else
	ktap_fail "sched reattach: a hardirq runtime attaches, re-attaches and detaches"
fi

if run_test "$PASS" hardirq && sudo bpftool struct_ops register "$BPF_OBJ" "$PIN"; then
	ktap_pass "sched pass: task class assigned correctly"
else
	ktap_fail "sched pass: task class assigned correctly"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

