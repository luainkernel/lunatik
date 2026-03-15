#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# KTAP helpers and lunatik test utilities.
# Source this file from each test script.

KTAP_COUNT=0
KTAP_PASS=0
KTAP_FAIL=0

ktap_header() { echo "KTAP version 1"; }
ktap_plan()   { echo "1..$1"; }
ktap_pass()   { KTAP_COUNT=$((KTAP_COUNT+1)); KTAP_PASS=$((KTAP_PASS+1)); echo "ok $KTAP_COUNT $*"; }
ktap_fail()   { KTAP_COUNT=$((KTAP_COUNT+1)); KTAP_FAIL=$((KTAP_FAIL+1)); echo "not ok $KTAP_COUNT $*"; }
ktap_totals() { echo "# Totals: pass:$KTAP_PASS fail:$KTAP_FAIL skip:0"; }

DMESG_LINE=0
mark_dmesg()  { DMESG_LINE=$(dmesg | wc -l); }
check_dmesg() {
	local errs
	errs=$(dmesg | tail -n +$((DMESG_LINE+1)) | grep -E "\.lua:[0-9]+:" || true)
	[ -z "$errs" ] && return 0
	ktap_fail "no Lua errors in kernel"
	echo "# $errs"
	return 1
}

run_script() {
	local output
	output=$(lunatik run "$@")
	echo "$output" | grep -qE "\.lua:[0-9]+:" || return 0
	ktap_fail "Lua error in script"
	echo "# $output"
	ktap_totals
	exit 1
}

# Each test script must define cleanup().
# fail <description> stops the script, calls cleanup, and exits non-zero.
fail() {
	ktap_fail "$*"
	echo "# FAIL: $*" >&2
	lunatik stop "${SCRIPT:-}" 2>/dev/null
	cleanup 2>/dev/null || true
	ktap_totals
	exit 1
}

