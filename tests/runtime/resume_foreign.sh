#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the runtime class check: runtime:resume() called on an
# object of another class (a data buffer here) must be refused, instead of
# having its private data used as a Lua state.
#
# Usage: sudo bash tests/runtime/resume_foreign.sh

SCRIPT="tests/runtime/resume_foreign"

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
ktap_pass "runtime:resume refuses an object of another class"

ktap_totals

