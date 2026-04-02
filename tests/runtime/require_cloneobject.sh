#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for lunatik_require using luaL_requiref (no file I/O).
# A data object is passed via resume() to a softirq receiver that never
# called require("data"). lunatik_cloneobject runs under the spinlock held
# by lunatik_monitorobject and must load the class via lunatik_require
# (opener field) without sleeping — otherwise "scheduling while atomic".
#
# Usage: sudo bash tests/runtime/require_cloneobject.sh

SCRIPT="tests/runtime/require_cloneobject"
MODULE="luadata"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

run_script "$SCRIPT"

check_dmesg || { ktap_totals; exit 1; }
ktap_pass "lunatik_require loads class via opener without file I/O"

ktap_totals

