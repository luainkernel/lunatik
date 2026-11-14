#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What the cases read the kernel log for: KTAP_ERRORS and its kernel half, KTAP_KERNEL_ERRORS,
# in tests/lib.sh, and check_dmesg and run_test, which read the log against them. Each case
# holds one line, spelled as dmesg prints it from the format string that prints it and matched
# by one alternative of the pattern alone, to both patterns and both functions, over a dmesg
# the script stubs to print that line:
# - a Lua error at a file's position, one at ?:?, which a chunk without debug information
#   gives, and a Lua warning: KTAP_ERRORS matches, its kernel half does not, and both
#   functions fail;
# - each head the kernel gives a warning, a sanitizer report, a sleep in atomic context, a
#   lockup and an oops on arm64 and x86: both patterns match, and both functions fail;
# - a line a script prints, headed DEBUG:, and one of debugobjects, headed ODEBUG:, which the
#   word boundary leaves out: neither pattern matches, and both functions pass.
# Nothing is loaded and nothing is written to the kernel log: the stub answers every dmesg the
# functions run, the clear of mark_dmesg included, run_test runs `true` for the CLI, and each
# function runs in a subshell with its output dropped, which keeps the not ok check_dmesg
# reports out of the output and the counts.
#
# Usage: sudo bash tests/dmesg/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

dmesg() { printf '%s\n' "$LINE"; }

# verdict <line>: E where KTAP_ERRORS matches the line, K where KTAP_KERNEL_ERRORS does, c
# where check_dmesg fails over it and r where run_test does, - for each that does not
verdict() {
	LINE="[ 1234.567890] $1"
	grep -qE "$KTAP_ERRORS" <<< "$LINE" && printf E || printf %s -
	grep -qE "$KTAP_KERNEL_ERRORS" <<< "$LINE" && printf K || printf %s -
	(check_dmesg > /dev/null) && printf %s - || printf c
	(CLI=true run_test > /dev/null) && printf %s - || printf r
}

# held <lua|kernel|none> <case> <line>
held() {
	local want got
	case "$1" in lua) want=E-cr ;; kernel) want=EKcr ;; none) want=---- ;; esac
	got=$(verdict "$3")
	if [ "$got" = "$want" ]; then
		ktap_pass "$2"
	else
		comment "$3: wanted $want, got $got (E KTAP_ERRORS, K KTAP_KERNEL_ERRORS, c check_dmesg, r run_test)"
		ktap_fail "$2"
	fi
}

ktap_header
ktap_plan 18

held lua "a Lua error at a position" "lunatik: /lib/modules/lua/tests/x.lua:12: boom"
held lua "a Lua error without debug information" "lunatik: ?:?: attempt to index a nil value"
held lua "a Lua warning" "Lua warning: deprecated"
held kernel "a kernel warning" "WARNING: CPU: 1 PID: 42 at kernel/sched/core.c:10 f+0x1/0x2"
held kernel "a UBSAN report" "UBSAN: shift-out-of-bounds in lib/x.c:1:2"
held kernel "an arm64 oops" "Internal error: synchronous external abort: 0000000096000010 [#1] PREEMPT SMP"
held kernel "a debug trap nobody owns" "Unexpected kernel BRK exception at EL1"
held kernel "scheduling while atomic" "BUG: scheduling while atomic: swapper/0/0/0x00000002"
held kernel "a sleep in atomic context" "BUG: sleeping function called from invalid context at kernel/x.c:1"
held kernel "a KFENCE report" "BUG: KFENCE: out-of-bounds read in f+0x1/0x2"
held kernel "a soft lockup" "watchdog: BUG: soft lockup - CPU#0 stuck for 26s! [x:1]"
held kernel "an x86 NULL dereference" "BUG: kernel NULL pointer dereference, address: 0000000000000000"
held kernel "an x86 oops" "Oops: 0002 [#1] PREEMPT SMP"
held kernel "an x86 protection fault" "general protection fault, probably for non-canonical address 0xdead: 0000 [#1] SMP"
held kernel "a BUG() hit" "kernel BUG at mm/slub.c:1!"
held kernel "an arm64 fault" "Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000"
held none "a script's DEBUG: line" "DEBUG: lunatik: a script's own line"
held none "a debugobjects line" "ODEBUG: Out of memory. ODEBUG disabled"

ktap_totals

