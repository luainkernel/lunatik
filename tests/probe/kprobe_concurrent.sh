#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the kprobe handler crash caused by spin_lock_bh in
# exception context (closes #96).
#
# Kprobe handlers fire via synchronous debug exception: irq_enter() is
# never called, so in_interrupt() returns false, but preemption is
# disabled throughout the kprobe handler execution.
#
# With LUNATIK_OPT_SOFTIRQ, lunatik_run() holds the runtime with
# spin_lock_bh. On unlock, spin_unlock_bh -> local_bh_enable ->
# do_softirq() fires before setup_singlestep completes, corrupting
# kprobe_ctlblk.
#
# This test registers kprobes on all syscalls, then launches one
# load-generating process per CPU so that concurrent handler firings across
# CPUs are likely. After three seconds the runtime is stopped; lunatik stop
# is wrapped in timeout to detect stop hangs.
#
# Without the fix the test triggers kernel errors in dmesg within the first
# few seconds of load.
#
# Usage: sudo bash tests/probe/kprobe_concurrent.sh

SCRIPT="tests/probe/kprobe_concurrent"
SLEEP=3

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

LOAD_PIDS=()

cleanup() {
	for pid in "${LOAD_PIDS[@]}"; do
		kill "$pid" 2>/dev/null
	done
	wait "${LOAD_PIDS[@]}" 2>/dev/null
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg
mark_ts=$(awk '{print $1}' /proc/uptime)

run_script "$SCRIPT" hardirq

# One load process per CPU to maximise the chance of concurrent handler
# firings on the same runtime across CPUs.
NCPU=$(nproc)
for i in $(seq 1 "$NCPU"); do
	( while true; do cat /proc/uptime > /dev/null 2>&1; done ) &
	LOAD_PIDS+=($!)
done

sleep $SLEEP

# Stop must complete within 5 s; timeout exit code 124 means a hang.
timeout 5 lunatik stop "$SCRIPT" 2>/dev/null
STOP_RET=$?

for pid in "${LOAD_PIDS[@]}"; do kill "$pid" 2>/dev/null; done
wait "${LOAD_PIDS[@]}" 2>/dev/null
LOAD_PIDS=()

[ $STOP_RET -eq 124 ] && fail "runtime stop hung (exceeded 5s timeout)"
ktap_pass "runtime stop completed within timeout"

check_dmesg || { ktap_totals; exit 1; }

sched=$(dmesg | awk -v ts="$mark_ts" \
	'match($0, /\[[ ]*([0-9]+\.[0-9]+)/, a) && a[1]+0 >= ts+0' | \
	grep -E "scheduling while atomic|BUG:|Oops:|kernel BUG at|general protection" || true)
[ -n "$sched" ] && fail "kernel error during concurrent kprobe handler firings: ${sched%%$'\n'*}"
ktap_pass "no kernel errors during concurrent kprobe handler firings"

ktap_totals

