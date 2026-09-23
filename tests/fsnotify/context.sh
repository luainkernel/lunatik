#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What the module refuses: a callback that is not a function, a path that does
# not resolve, and the whole module from a softirq runtime — marking sleeps and
# so does the callback, so the class carries no interrupt context and the
# constructor says so rather than deadlocking later. A percpu runtime is refused
# at the constructor too, with the core's percpu refusal. A permission mask is
# refused only where the kernel was built without the hooks that would reach it,
# so that case takes either answer and asserts the message names the config.
# find refuses a path that does not resolve and an invalid kind as mark does,
# and mark:mask checks a permission mask the way mark does, before it removes
# the mark, so a refusal leaves the mark with the mask it had.
#
# A runtime takes as many watches as it likes: the reentrancy guard reads the
# runtime lock's owner rather than a per-watch task, so a second watch is not a
# route past it; context.lua checks that both are constructed and stop cleanly.
#
# context.lua drives all of that plus the successes they are measured against
# through pcall and reports each with util.test. The shell counts its PASS lines
# rather than only looking for a FAIL: a case that never ran leaves neither.
# refused.lua is a separate script because the runtime context and the percpu
# option are chosen on the lunatik run command line; it runs once as each.
#
# Usage: sudo bash tests/fsnotify/context.sh

SCRIPT="tests/fsnotify/context"
REFUSED="tests/fsnotify/refused"
SCRATCH="/tmp/lunatik-fsnotify"
CASES=9

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$REFUSED" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

mkdir -p -m 0700 "$SCRATCH"

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
refusals=$(dmesg_since)
lunatik stop "$SCRIPT" 2>/dev/null

mark_dmesg
softirq=$(lunatik run "$REFUSED" softirq 2>&1)
lunatik stop "$REFUSED" 2>/dev/null

percpu=$(lunatik run "$REFUSED" percpu 2>&1)
lunatik stop "$REFUSED" 2>/dev/null
refused=$(dmesg_since)

passed=$(echo "$refusals" | grep -c "PASS	")
[ "$passed" -eq "$CASES" ] || \
	fail "$passed of $CASES cases passed: $(echo "$refusals" | grep "FAIL	")"
ktap_pass "watch, mark, mask and find report what they reject and still take a directory"

echo "$softirq" | grep -qF "runtime context mismatch" || \
	fail "expected 'runtime context mismatch' from a softirq runtime, got: $softirq"
ktap_pass "fsnotify.watch refuses a softirq runtime"

echo "$percpu" | grep -qF "not allowed in a percpu runtime" || \
	fail "expected 'not allowed in a percpu runtime' from a percpu runtime, got: $percpu"
ktap_pass "fsnotify.watch refuses a percpu runtime"

errs=$(printf '%s\n%s\n' "$refusals" "$refused" | grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals

