#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for percpu:resume: the objects it delivers reach every
# runtime, each of which marks its own CPU id in the shared rcu.tables the
# driver then reads, for a process set and for a softirq one, which is what a
# packet hook is, and two objects are marked in the order they were passed;
# what a runtime yields is dropped, and the runtimes are resumable past their
# yield; a hardirq set, whose runtimes resume under spin_lock_irqsave, takes
# what it is given and raises when it is given nothing; the error a runtime
# raises comes back naming it and leaves that runtime dead, so the next resume
# fails on it again, while a value that cannot cross is refused before the
# resume, leaving the runtimes where they yielded; and resume is refused on a
# stopped object, whose runtimes have no state left, and on an object of
# another class reached through the percpu metatable.
#
# Usage: sudo bash tests/runtime/resume_percpu.sh

SCRIPT="tests/runtime/resume_percpu"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "percpu:resume delivers to every runtime of a process, softirq and hardirq set, raises what one raises, and refuses a stopped object and another class"

ktap_totals

