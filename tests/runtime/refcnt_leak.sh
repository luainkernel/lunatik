#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for module refcnt leak in lunatik_newruntime error path.
#
# A script calls require("netfilter") and then netfilter.register() once
# (successfully, runtime kref → 2), then errors.  Without the fix, the error
# path never calls lua_close(), so the LSTRMEM string holding the
# luanetfilter module reference is never freed and luanetfilter's use-count
# stays elevated.  With the fix, lua_close() is called explicitly before
# lunatik_putobject(), GC runs, the hook is finalized, and the use-count is
# restored.
#
# Usage: sudo bash tests/runtime/refcnt_leak.sh

SCRIPT="tests/runtime/refcnt_leak"
PERCPU="tests/runtime/refcnt_leak_percpu"
MODULE="luanetfilter"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$PERCPU" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

before=$(cat /sys/module/$MODULE/refcnt 2>/dev/null) || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

# run the script in a non-sleepable runtime (required for netfilter hooks);
# the failure below is the intentional one
output=$(lunatik run "$SCRIPT" softirq 2>&1)
echo "$output" | grep -q "intentional error after first register" || \
	fail "script did not reach the intentional error: $output"

check_dmesg || { ktap_totals; exit 1; }

after=$(cat /sys/module/$MODULE/refcnt 2>/dev/null)
[ "$before" = "$after" ] || fail "$MODULE refcnt leaked: $before -> $after (fix lunatik_newruntime error path)"

ktap_pass "$MODULE refcnt restored after failed script"

[ "$(sed 's/.*-//' /sys/devices/system/cpu/possible)" -gt 0 ] || {
	echo "# SKIP: the percpu rollback needs a runtime before the one that fails"
	ktap_skip "$MODULE refcnt restored after a percpu script failed on its last runtime"
	ktap_totals
	exit 0
}

mark_dmesg
output=$(lunatik run "$PERCPU" softirq percpu 2>&1)
echo "$output" | grep -q "intentional error on the last runtime" || \
	fail "percpu script did not reach the intentional error: $output"
check_dmesg || { ktap_totals; exit 1; }
after=$(cat /sys/module/$MODULE/refcnt 2>/dev/null)
[ "$before" = "$after" ] || fail "$MODULE refcnt leaked: $before -> $after (the rollback left a hook of an earlier runtime)"
ktap_pass "$MODULE refcnt restored after a percpu script failed on its last runtime"

ktap_totals

