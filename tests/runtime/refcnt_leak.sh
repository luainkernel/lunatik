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
MODULE="luanetfilter"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 1

before=$(cat /sys/module/$MODULE/refcnt 2>/dev/null) || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

# run the script in a non-sleepable runtime (required for netfilter hooks);
# it is expected to fail — ignore the error
lunatik run "$SCRIPT" false 2>/dev/null || true

check_dmesg || { ktap_totals; exit 1; }

after=$(cat /sys/module/$MODULE/refcnt 2>/dev/null)
[ "$before" = "$after" ] || fail "$MODULE refcnt leaked: $before -> $after (fix lunatik_newruntime error path)"

ktap_pass "$MODULE refcnt restored after failed script"

ktap_totals

