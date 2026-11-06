#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.acompress callbacks. Four compressions submit the decompression of their output from their
# callbacks, on a request of their own, and each prints "ACOMPRESS callback ok <i>" when it gives the
# input back, or "ACOMPRESS callback failed <i>" with the reason. A callback that raises leaves its
# request usable: the next operation submitted on it prints "ACOMPRESS callback reusable".
#
# The script body returns without waiting. An asynchronous implementation runs a callback only once
# the body is done and the runtime is free, so the lines are read from dmesg, ten seconds at most,
# after the run. The raise is the one Lua error the run provokes on purpose, and check_dmesg filters it.
#
# Usage: sudo bash tests/crypto/acompress_callback.sh

SCRIPT=tests/crypto/acompress_callback
COUNT=4
RAISE="ACOMPRESS callback raises on purpose"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

ok() { dmesg_since | grep -cF "ACOMPRESS callback ok $1"; }
failed() { dmesg_since | grep -cF "ACOMPRESS callback failed"; }

complete() {
	local index
	[ "$(failed)" -eq 0 ] || return 1
	for index in $(seq "$COUNT"); do
		[ "$(ok "$index")" -eq 1 ] || return 1
	done
	dmesg_since | grep -qF "ACOMPRESS callback reusable"
}

mark_dmesg
output=$(${CLI:-lunatik} run "$SCRIPT" 2>&1)
case "$output" in
*"the kernel serves no lz4"*)
	ktap_skip "crypto/acompress_callback: the kernel serves no lz4"
	ktap_totals
	exit 0 ;;
"") ;;
*)
	comment "$output"
	ktap_fail "crypto/acompress_callback"
	ktap_totals
	exit 1 ;;
esac

RESULT=0
if TRIES=100 awaited complete; then
	ktap_pass "crypto/acompress_callback"
else
	ktap_fail "crypto/acompress_callback: the callbacks did not all report within ten seconds"
	failures=$(dmesg_since | grep -F "ACOMPRESS callback failed" || true)
	[ -n "$failures" ] && comment "$failures"
	RESULT=1
fi
check_dmesg "$RAISE" || RESULT=1
ktap_totals || RESULT=1
exit $RESULT

