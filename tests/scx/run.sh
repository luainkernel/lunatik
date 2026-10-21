#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the scx tests and reports aggregated KTAP results.
#
# On a kernel without sched_ext (its kset is /sys/kernel/sched_ext) the module
# offers attach and detach, and the unsupported case checks that attach raises
# EOPNOTSUPP and that detach returns nothing; it skips on a kernel with sched_ext. Two guard cases need no scheduler: a
# sleepable runtime is refused, and a hardirq runtime attaches, re-attaches and
# detaches.
#
# The pass cases register a struct_ops scheduler whose enqueue calls bpf_luascx_run
# with cls filled with a value no decision writes, and records in a pinned map what
# the kfunc returned and left in cls at the first enqueue of each task named scx_*.
# Its select_cpu dispatches nothing, so every wakeup reaches enqueue. The suite starts
# one task per cell, a sleep run under the cell's name that wakes once, and the
# callback of pass.lua reads that name through ctx:task() and answers with the
# cell's decision: nothing, a raise, a nil dispatch queue or slice, a dispatch queue
# as a string, a slice that is not a number, linux.scx's LOCAL, GLOBAL and LOCAL_ON
# with slice INF or a slice of its own, and a detach from the callback; the last
# task runs after it. The task of the LOCAL_ON cell is pinned to the last online
# CPU and answered with that CPU, so a decision that lost the CPU shows on a host of
# two CPUs or more. Every other task takes the default dispatch queue. Once the
# scheduler is unregistered and its runtime stopped, record.lua compares each record
# with the values linux/sched/ext.h gives and reports what it read; a kernel that
# disabled the scheduler, or a Lua error or kernel warning in dmesg, fails every cell.
# These skip when the kernel has no sched_ext, the module lacks BTF, bpftool, clang
# or taskset is unavailable, or another sched_ext scheduler is enabled.
#
# The runqueue cases register a scheduler of their own, whose enqueue calls
# bpf_luascx_run for runqueue.lua and whose select_cpu dispatches nothing, so that
# every wakeup reaches enqueue, with the runqueue lock of its CPU held. The callback
# takes one step per enqueue: it calls complete and a mailbox's send, records in an
# rcu.table of _ENV that each raised "not allowed under the runqueue lock" and that
# send left its message queued, and lets complete's raise reach the dispatch; it then
# returns a dispatch queue that is not a number, and then detaches. The scheduler
# calls the kfunc for its first four enqueues, so the fourth finds no callback, and
# for no more: each one past it would log that line again, and ten of them rate limit
# the line of a run that follows within five seconds. Three naps of a sleep enqueue
# more tasks than the four.
# Once the scheduler is unregistered and its runtime stopped, runqueue_check.lua
# reads the record, and the dispatch must have logged the raise, the refused
# decision and a missing callback, while any other Lua error or a kernel warning
# fails every case. A kprobe on vprintk_emit reads the level and the format of every
# write while the scheduler is registered: the dispatch's formats carry the module's
# name, and each must be written at LOGLEVEL_SCHED, the level that leaves the console
# to an irq_work; that case skips where the kprobe cannot be placed. The runqueue
# cases skip where the pass cases do, and while another sched_ext scheduler is
# enabled.
#
# Usage: sudo bash tests/scx/run.sh

MODULE="luascx"
UNSUPPORTED="tests/scx/unsupported"
SLEEPABLE="tests/scx/attach_sleepable"
REATTACH="tests/scx/reattach"
RUNQUEUE="tests/scx/runqueue"
RUNQUEUE_CHECK="tests/scx/runqueue_check"
RUNQUEUE_OPS="runqueue_ops"
# the dispatch's line for complete's raise, a Lua error on purpose
RUNQUEUE_RAISED="$MODULE: .*: not allowed under the runqueue lock"
# the runqueue cases, as runqueue_check.lua names them, the lines each reads the dispatch logged, one per line, and its title;
# the last title is the case runqueue_deferred reads alone
RUNQUEUE_CASES=(refused raised detached)
RUNQUEUE_LOGGED=("" "$RUNQUEUE_RAISED"$'\n'"$MODULE: invalid task class" "$MODULE: no callback attached")
RUNQUEUE_TITLES=(
	"scx runqueue: complete and a mailbox's send raise \"not allowed under the runqueue lock\" in the callback"
	"scx runqueue: the dispatch logs an error the callback raises and a decision it refuses"
	"scx runqueue: a dispatch that finds no callback logs \"no callback attached\""
	"scx runqueue: the dispatch writes its lines deferred, at LOGLEVEL_SCHED"
)
# the kprobe that reads vprintk_emit's level and format, and how it prints LOGLEVEL_SCHED
RUNQUEUE_WRITES="scx_runqueue/write"
RUNQUEUE_WRITE='vprintk_emit level=$arg2:s32 fmt=+0($arg4):string'
RUNQUEUE_SCHED="level=-2"
PASS="tests/scx/pass"
RECORD="tests/scx/record"
OPS="luascx_ops"
PIN="/sys/fs/bpf/scx_record"
NAP=0.05

# the cells: the comm each task takes, which pass.lua answers and record.lua reads, and its title
CELLS=(scx_none scx_raise scx_nil_dsq scx_nil_slice scx_str_dsq scx_bool_slice scx_local scx_global scx_local_on
	scx_detach scx_after)
TITLES=(
	"scx pass: a callback that returns nothing leaves cls as it was"
	"scx pass: a callback that raises leaves cls as it was"
	"scx pass: a nil dispatch queue takes SCX_DSQ_GLOBAL"
	"scx pass: a nil slice takes SCX_SLICE_DFL"
	"scx pass: a dispatch queue as a string is refused and leaves cls as it was"
	"scx pass: a slice that is not a number is refused and leaves cls as it was"
	"scx pass: linux.scx.dsq.LOCAL and slice.INF reach cls"
	"scx pass: linux.scx.dsq.GLOBAL and a slice of the callback's reach cls"
	"scx pass: linux.scx.dsq.LOCAL_ON ORed with the task's CPU reaches cls"
	"scx pass: a callback that detaches still decides for its task"
	"scx pass: once detached, the kfunc returns -1 and leaves cls as it was"
)

DIR="$(dirname "$(readlink -f "$0")")"
TASKS=""

source "$DIR/../lib.sh"

ktap_header
ktap_plan $((3 + ${#RUNQUEUE_TITLES[@]} + ${#CELLS[@]}))

skip_rest()
{
	echo "# SKIP: $1"
	ktap_skip "scx attach: refuses a sleepable runtime"
	for title in "${RUNQUEUE_TITLES[@]}"; do ktap_skip "$title"; done
	ktap_skip "scx reattach: a hardirq runtime attaches, re-attaches and detaches"
	cells skip "$1"
	ktap_totals
	exit
}

# cells <skip|fail> <reason>: every cell skips or fails with the reason
cells()
{
	local title

	for title in "${TITLES[@]}"; do
		"ktap_$1" "$title: $2"
	done
}

if ! cat /sys/module/$MODULE/refcnt > /dev/null 2>&1; then
	ktap_skip "scx unsupported: attach raises EOPNOTSUPP and detach does nothing without sched_ext"
	skip_rest "$MODULE not loaded"
fi

cleanup()
{
	bpftool struct_ops unregister name "$OPS" 2>/dev/null
	bpftool struct_ops unregister name "$RUNQUEUE_OPS" 2>/dev/null
	lunatik stop "$UNSUPPORTED" 2>/dev/null
	lunatik stop "$SLEEPABLE" 2>/dev/null
	lunatik stop "$RUNQUEUE" 2>/dev/null
	kprobe_remove "$RUNQUEUE_WRITES"
	lunatik stop "$REATTACH" 2>/dev/null
	lunatik stop "$PASS" 2>/dev/null
	rm -f "$PIN"
	[ -z "$TASKS" ] || rm -rf "$TASKS"
}
trap cleanup EXIT
cleanup

if [ -d /sys/kernel/sched_ext ]; then
	echo "# SKIP: kernel with sched_ext"
	ktap_skip "scx unsupported: attach raises EOPNOTSUPP and detach does nothing without sched_ext"
elif run_test "$UNSUPPORTED"; then
	ktap_pass "scx unsupported: attach raises EOPNOTSUPP and detach does nothing without sched_ext"
else
	ktap_fail "scx unsupported: attach raises EOPNOTSUPP and detach does nothing without sched_ext"
fi

[ -d /sys/kernel/sched_ext ] || skip_rest "kernel without sched_ext"
[ -f /sys/kernel/btf/$MODULE ] || skip_rest "$MODULE built without BTF (make btf_install, rebuild)"
command -v bpftool > /dev/null 2>&1 || skip_rest "bpftool not available"
command -v clang > /dev/null 2>&1 || skip_rest "clang not available"
command -v taskset > /dev/null 2>&1 || skip_rest "taskset not available"

make -C "$DIR" || { ktap_fail "failed to build the sched_ext program"; ktap_totals; exit 1; }

if run_test "$SLEEPABLE"; then
	ktap_pass "scx attach: refuses a sleepable runtime"
else
	ktap_fail "scx attach: refuses a sleepable runtime"
fi

# runqueue_cases <skip|fail> <reason>: every runqueue case skips or fails with the reason
runqueue_cases()
{
	local title

	for title in "${RUNQUEUE_TITLES[@]}"; do
		"ktap_$1" "$title: $2"
	done
}

# runqueue_verdict <i> <log>: runqueue_check.lua passed case <i>, and <log> holds each of its lines
runqueue_verdict()
{
	local line missing=""

	while IFS= read -r line; do
		[ -z "$line" ] || grep -qE "$line" <<< "$2" || missing="$missing $line"
	done <<< "${RUNQUEUE_LOGGED[$1]}"
	if passed "${RUNQUEUE_CASES[$1]}" && [ -z "$missing" ]; then
		ktap_pass "${RUNQUEUE_TITLES[$1]}"
	else
		ktap_fail "${RUNQUEUE_TITLES[$1]}"
		comment "$(dmesg_since | grep -E "${RUNQUEUE_CASES[$1]}[[:space:]]")"
		[ -z "$missing" ] || comment "not logged:$missing"
	fi
}

# the level of each write the dispatch made, a vprintk_emit whose format carries the module's name
runqueue_levels()
{
	grep -a "fmt=\".*$MODULE: " "$TRACING/instances/${RUNQUEUE_WRITES%%/*}/trace" 2>/dev/null | grep -o 'level=[-0-9]*'
}

# runqueue_deferred <placed> <levels>: the kprobe was placed, and LOGLEVEL_SCHED is the one level the dispatch wrote at
runqueue_deferred()
{
	local title=${RUNQUEUE_TITLES[${#RUNQUEUE_CASES[@]}]} levels=${2//$'\n'/ }

	if [ "$1" -eq 0 ]; then
		ktap_skip "$title: couldn't place a kprobe on vprintk_emit"
	elif [ "$levels" = "$RUNQUEUE_SCHED" ]; then
		ktap_pass "$title"
	else
		ktap_fail "$title"
		comment "written at: ${levels:-no level, the kprobe read no write of the dispatch}"
	fi
}

# the scheduler, the runtime and the kprobe are gone before the record is read
runqueue()
{
	local log errs i levels placed=0

	if [ "$(cat /sys/kernel/sched_ext/state)" != disabled ]; then
		runqueue_cases skip "another sched_ext scheduler is enabled"
		return
	fi
	run_test --context=hardirq "$RUNQUEUE" || { runqueue_cases fail "$RUNQUEUE did not run"; return; }
	kprobe_place "$RUNQUEUE_WRITES" "$RUNQUEUE_WRITE" && placed=1
	if ! bpftool struct_ops register "$DIR/scx_runqueue.bpf.o" > /dev/null; then
		kprobe_remove "$RUNQUEUE_WRITES"
		lunatik stop "$RUNQUEUE"
		runqueue_cases fail "the scheduler did not register"
		return
	fi
	for _ in 1 2 3; do
		sleep 0.05
	done
	bpftool struct_ops unregister name "$RUNQUEUE_OPS" > /dev/null
	lunatik stop "$RUNQUEUE"
	log=$(dmesg_since)
	levels=$(runqueue_levels | sort -u)
	kprobe_remove "$RUNQUEUE_WRITES"
	errs=$(grep -E "$KTAP_ERRORS" <<< "$log" | grep -vE "$RUNQUEUE_RAISED")
	if [ -n "$errs" ]; then
		comment "$errs"
		runqueue_cases fail "a Lua error or a kernel warning"
		return
	fi
	run_test "$RUNQUEUE_CHECK"
	for i in "${!RUNQUEUE_CASES[@]}"; do
		runqueue_verdict "$i" "$log"
	done
	runqueue_deferred "$placed" "$levels"
}

runqueue

if run_test --context=hardirq "$REATTACH"; then
	ktap_pass "scx reattach: a hardirq runtime attaches, re-attaches and detaches"
else
	ktap_fail "scx reattach: a hardirq runtime attaches, re-attaches and detaches"
fi

# nap <comm> [<cpu>]: a task named <comm>, pinned to <cpu> where one is given, sleeps once, whose
# wakeup reaches the scheduler's enqueue; argv[0] stays sleep for a sleep that reads its name from it
nap()
{
	(
		[ -z "$2" ] || taskset -pc "$2" $BASHPID > /dev/null
		exec -a sleep "$TASKS/$1" "$NAP"
	)
}

# the record of each cell, read once its scheduler and runtime are gone
record()
{
	local output i

	output=$(lunatik run "$RECORD" 2>&1)
	rm -f "$PIN"
	[ -z "$output" ] || { comment "$output"; cells fail "$RECORD did not run"; return; }
	for i in "${!CELLS[@]}"; do
		if passed "${CELLS[$i]}"; then
			ktap_pass "${TITLES[$i]}"
			comment "$(dmesg_since | grep -F "scx record: ${CELLS[$i]} ")"
		else
			ktap_fail "${TITLES[$i]}"
			comment "$(dmesg_since | grep -E "${CELLS[$i]}[[:space:]]")"
		fi
	done
}

pass()
{
	local cell last state errs

	if [ "$(cat /sys/kernel/sched_ext/state)" != disabled ]; then
		cells skip "another sched_ext scheduler is enabled"
		return
	fi
	run_test --context=hardirq "$PASS" || { cells fail "$PASS did not run"; return; }
	bpftool struct_ops register "$DIR/scx_pass.bpf.o" > /dev/null || { cells fail "the scheduler did not register"; return; }

	TASKS=$(mktemp -d)
	for cell in "${CELLS[@]}"; do
		ln -sf "$(command -v sleep)" "$TASKS/$cell"
	done
	last=$(sed 's/.*[-,]//' /sys/devices/system/cpu/online)
	for cell in "${CELLS[@]}"; do
		if [ "$cell" = scx_local_on ]; then
			nap "$cell" "$last"
		else
			nap "$cell"
		fi
	done

	state=$(cat /sys/kernel/sched_ext/state)
	bpftool struct_ops unregister name "$OPS" > /dev/null
	lunatik stop "$PASS"
	errs=$(dmesg_since | grep -E "$KTAP_ERRORS")
	if [ "$state" != enabled ]; then
		comment "$(dmesg_since | grep -F sched_ext | tail -5)"
		cells fail "the kernel disabled the scheduler"
	elif [ -n "$errs" ]; then
		comment "$errs"
		cells fail "a Lua error or a kernel warning"
	else
		record
	fi
}

pass

ktap_totals

