#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the sched tests and reports aggregated KTAP results.
#
# Two guard cases need no scheduler: a sleepable runtime is refused, and a
# hardirq runtime attaches, re-attaches and detaches. The pass case registers a
# struct_ops scheduler whose enqueue calls bpf_luasched_run, so every enqueue on
# the host reaches the Lua callback while it is registered; the callback reports
# once, and that line in dmesg with no Lua error is the proof. The scheduler is
# unregistered before its runtime stops. Skipped when the kernel has no
# sched_ext (its kset is /sys/kernel/sched_ext), the module lacks BTF, or
# bpftool or clang is unavailable.
#
# Usage: sudo bash tests/sched/run.sh

MODULE="luasched"
SLEEPABLE="tests/sched/attach_sleepable"
REATTACH="tests/sched/reattach"
PASS="tests/sched/pass"
OPS="luasched_ops"
SETTLE=1

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

ktap_header
ktap_plan 3

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "sched attach: refuses a sleepable runtime"
	ktap_skip "sched reattach: a hardirq runtime attaches, re-attaches and detaches"
	ktap_skip "sched pass: the callback runs from the scheduler's enqueue"
	ktap_totals
	exit 0
}

[ -d /sys/kernel/sched_ext ] || skip_all "kernel without sched_ext"
cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
[ -f /sys/kernel/btf/$MODULE ] || skip_all "$MODULE built without BTF (make btf_install, rebuild)"
command -v bpftool > /dev/null 2>&1 || skip_all "bpftool not available"
command -v clang > /dev/null 2>&1 || skip_all "clang not available"

cleanup()
{
	bpftool struct_ops unregister name "$OPS" 2>/dev/null
	lunatik stop "$SLEEPABLE" 2>/dev/null
	lunatik stop "$REATTACH" 2>/dev/null
	lunatik stop "$PASS" 2>/dev/null
}
trap cleanup EXIT
cleanup

make -C "$DIR" || { ktap_fail "failed to build the sched_ext program"; ktap_totals; exit 1; }

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

# the callback fires on the host's own enqueues; a moment of registration is enough for one
if run_test "$PASS" hardirq && bpftool struct_ops register "$DIR/sched_pass.bpf.o" > /dev/null; then
	sleep $SETTLE
	bpftool struct_ops unregister name "$OPS"
	if dmesg_since | grep -q "sched pass test pass" && ! dmesg_since | grep -qE "\.lua:[0-9]+:"; then
		ktap_pass "sched pass: the callback runs from the scheduler's enqueue"
	else
		ktap_fail "sched pass: the callback runs from the scheduler's enqueue"
		comment "$(dmesg_since | tail -5)"
	fi
else
	ktap_fail "sched pass: the callback runs from the scheduler's enqueue"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

