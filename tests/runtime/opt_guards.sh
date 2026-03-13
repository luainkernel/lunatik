#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests lunatik_opt_t guards:
#   - SINGLE objects are rejected by resume() and _ENV["key"] = obj
#   - MONITOR/NONE objects pass through resume() without error
#
# Usage: sudo bash tests/runtime/opt_guards.sh

SCRIPT="tests/runtime/opt_guards"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg

output=$(lunatik run "$SCRIPT")
if echo "$output" | grep -qE "\.lua:[0-9]+:"; then
	ktap_fail "Lua error in script"
	echo "# $output"
	ktap_totals
	exit 1
fi

check_dmesg || { ktap_totals; exit 1; }
ktap_pass "opt guards: SINGLE rejected, MONITOR/NONE accepted"

ktap_totals
