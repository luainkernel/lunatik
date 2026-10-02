#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The end of a runtime that started a thread, when a softirq or hardirq
# runtime's write drops its last reference, stops the thread, and nothing
# sleeps under that write.
#
# An rcu.table entry's put runs in its writer's context, so a runtime whose
# last reference an entry holds is put, when a softirq or hardirq runtime
# removes the entry, under that runtime's lock: with BH off for a softirq one,
# with IRQs off for a hardirq one, where the core hands its close to a kernel
# worker. atomic.lua is spawned, since a thread is started from an armed
# runtime and not from a script body. For each of the two contexts it has a
# creator runtime start a thread whose body waits three seconds at most for a
# stop, stores the creator in an rcu.table, drops its own handles and resumes a
# runtime of that context that removes the entry: the creator closes on the
# worker, its end stops the thread there, and the body sees the stop. A stop
# made under the writer's lock would wait for the body in atomic context, where
# the kernel logs "BUG: scheduling while atomic" (__schedule_bug,
# kernel/sched/core.c) and the task sleeps with BH or IRQs off; the test
# asserts that line absent. A core that closes the creator under that lock
# makes that stop, so the test skips unless the loaded lunatik lists
# lunatik_deferirq, which came with the deferred close, in /proc/kallsyms.
#
# Usage: sudo bash tests/thread/atomic.sh

SCRIPT="tests/thread/atomic"
MODULE="lunatik"
DEFER="lunatik_deferirq"
ATOMIC="BUG: scheduling while atomic"
TRIES=100

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/driver.sh"

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

grep -Eq " $DEFER[[:space:]]\[$MODULE\]$" /proc/kallsyms 2>/dev/null ||
	skip_all "no $DEFER in the loaded $MODULE: the end of a runtime would stop its thread in atomic context"

ktap_header
ktap_plan 4

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
awaited reported "hardirq"
lunatik stop "$SCRIPT" > /dev/null 2>&1

verdict "softirq" "the end of a runtime a softirq runtime's write drops stops its thread on a worker"
verdict "hardirq" "the end of a runtime a hardirq runtime's write drops stops its thread on a worker"

dmesg_since | grep -qF "$ATOMIC" && fail "a close in atomic context slept: $(dmesg_since | grep -F "$ATOMIC" | head -1)"
ktap_pass "nothing sleeps under the write that drops a runtime that started a thread"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

