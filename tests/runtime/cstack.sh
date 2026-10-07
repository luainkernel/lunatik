#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A recursion that crosses C raises "C stack overflow" once it has used the
# kernel stack the core allows past where it entered Lua, before that stack
# runs out, on every route that carries the recursion on.
#
# cstack.lua recurses from its body, which runs on the stack the CLI's write
# entered the driver on, through pcall, through coroutine.wrap, whose coroutines
# each hold a Lua stack of their own, so only the C stack bounds them, through an
# __index function and through rcu.foreach; it loads a chunk whose parentheses
# nest past the budget in the parser; it recurses through an __index function
# that collects garbage with a finalizer at each level, so that some level's
# collection runs where the finalizer's own call would cross the budget, and
# every finalizer has run once it is over; it creates cstack_self, whose script
# creates itself, so each runtime is a new state whose count of C levels starts
# over; and it resumes cstack_resumed, whose body recurses through pcall on the
# resumer's stack. Under xpcall, a message handler that recurses through C past
# the budget in turn ends the call with "error in error handling" rather than
# recursing into the handler. cstack_thread is spawned, and its body, which
# the core enters through lunatik_run in a kernel thread, recurses through pcall
# too and returns. Each reports whether the error it caught is the expected one.
# At the deepest level a pcall still enters, the driver also loads a chunk whose
# functions nest ten deep and dumps the function it came from with string.dump,
# both counted a C level per nested function, and checks that the chunk
# loads and dumps where the stack is shallow; and the CLI runs a chunk lunatic
# compiled with functions nested 98 deep, which the core refuses at its load on a
# 16 KB stack and runs on a stack that holds it, a 64 KB or a KASAN one, where the
# case skips. That last case runs only once this run's load at the deepest level
# raised, since on a core that does not count the nesting it loads it is the
# overflow itself.
# A build without the budget does not fail these cases, it overflows the kernel
# stack and takes the host down, so the test skips unless the loaded core has
# lunatik_maxccalls in /proc/kallsyms.
#
# Usage: sudo bash tests/runtime/cstack.sh

SCRIPT="tests/runtime/cstack"
THREAD="tests/runtime/cstack_thread"
DEEP="tests/runtime/cstack_deep"
DEPTH=98	# nested functions lunatic compiles from valid source (#1775)
MODULE="lunatik"
BUDGET="lunatik_maxccalls"
WAIT=50	# tenths of a second the spawned body has to report

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$THREAD" > /dev/null 2>&1
	lunatik stop "$DEEP" > /dev/null 2>&1
	rm -f "/lib/modules/lua/$DEEP.lua"
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 15

grep -Eq " $BUDGET[[:space:]]\[$MODULE\]$" /proc/kallsyms 2> /dev/null || {
	echo "# SKIP: the loaded $MODULE has no $BUDGET: a recursion through C would overflow the kernel stack"
	ktap_totals
	exit 0
}

reported()
{
	dmesg_since | grep -cF "cstack test: $1 raises"
}

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null 2>&1
for route in pcall coroutine.wrap __index rcu.foreach load undump string.dump runtime resume; do
	[ "$(reported "$route")" = 1 ] || fail "a recursion through $route did not raise C stack overflow"
	ktap_pass "a recursion through $route raises C stack overflow"
done
[ "$(reported "collection")" = 1 ] || fail "a collection near the budget dropped a finalizer"
ktap_pass "a collection near the budget leaves its finalizers for later"
[ "$(reported "message handler")" = 1 ] || fail "a recursing message handler did not end in error in error handling"
ktap_pass "a recursing message handler ends in error in error handling"
dmesg_since | grep -qF "cstack test: a chunk loads and dumps" || fail "a chunk nested ten deep did not load or dump"
ktap_pass "a chunk nested ten deep loads and dumps where the stack is shallow"

output=$(lunatik spawn "$THREAD" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
for _ in $(seq $WAIT); do
	[ "$(reported thread)" = 1 ] && break
	sleep 0.1
done
lunatik stop "$THREAD" > /dev/null 2>&1
[ "$(reported thread)" = 1 ] || fail "a recursion in a kernel thread's body did not raise C stack overflow"
ktap_pass "a recursion in a kernel thread's body raises C stack overflow"

if ! command -v lunatic > /dev/null; then
	ktap_skip "a chunk lunatic nests $DEPTH deep: lunatic is not installed"
else
	{ printf 'return '; printf 'function() return %.0s' $(seq $DEPTH); printf '0'; printf ' end%.0s' $(seq $DEPTH); echo; } |
		lunatic -s -o "/lib/modules/lua/$DEEP.lua" - || fail "lunatic did not compile $DEPTH nested functions"
	cli run "$DEEP"
	lunatik stop "$DEEP" > /dev/null 2>&1
	if [ $status = 0 ]; then
		ktap_skip "a chunk lunatic nests $DEPTH deep: this kernel's stack holds it"
	else
		echo "$err" | grep -qF "lunatik: C stack overflow" ||
			fail "a chunk lunatic nests $DEPTH deep was not refused: $err"
		ktap_pass "a chunk lunatic nests $DEPTH deep raises C stack overflow when the core loads it"
	fi
fi

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

