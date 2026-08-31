#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests luathread:task(), which returns a task object for the thread's kernel task.
#
# Case 1 (current): thread.current():task() is a usable task object (pid, comm, tgid).
# Case 2 (running): the object of a spawned thread, reached through lunatik._ENV.threads,
#   reports that thread: its comm is the thread name and its pid is not the caller's.
# Case 3 (exited): once the thread body has returned, thread->task is NULL and the
#   methods of the returned object raise instead of dereferencing it.
#
# Usage: sudo bash tests/thread/task.sh

SCRIPT_CURRENT="tests/thread/task"
SCRIPT_SPAWNED="tests/thread/task_spawned"
SCRIPT_EXITED="tests/thread/task_exited"
DUMMY="tests/thread/dummy"
EXIT="tests/thread/exit"
SLEEP=1

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT_CURRENT" 2>/dev/null
	lunatik stop "$SCRIPT_SPAWNED" 2>/dev/null
	lunatik stop "$SCRIPT_EXITED"  2>/dev/null
	lunatik stop "$DUMMY"          2>/dev/null
	lunatik stop "$EXIT"           2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

# Case 1: the current task
mark_dmesg
run_script "$SCRIPT_CURRENT"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "thread.current():task() returns a usable task object"

# Case 2: a running thread
mark_dmesg
output=$(lunatik spawn "$DUMMY" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
run_script "$SCRIPT_SPAWNED"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "task() of a running thread reports that thread"

# Case 3: a thread whose body has returned
mark_dmesg
output=$(lunatik spawn "$EXIT" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
sleep $SLEEP
run_script "$SCRIPT_EXITED"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "task() of an exited thread raises on use"

ktap_totals

