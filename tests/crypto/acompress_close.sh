#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A request closed from the callback a synchronous driver runs during compress is refused with "not
# allowed from the runtime itself": the callback runs inside the monitored method, which holds the
# request's lock that close takes. The request closes once the call returned.
#
# A build without the refusal waits on that lock forever and wedges the runtime, so the case runs
# only when the module file carries the refusal's message and the loaded luacrypto, if any, is that
# file. It skips where the kernel serves no lz4, and where the driver serving it completes
# asynchronously, whose callback runs after the call.
#
# Usage: sudo bash tests/crypto/acompress_close.sh

SCRIPT=tests/crypto/acompress_close
MODULE=luacrypto
OWNER="not allowed from the runtime itself"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

module_refuses() {
	local ko loaded
	ko=$(modinfo -n "$MODULE" 2>/dev/null)
	[ -n "$ko" ] && grep -aqF "$OWNER" "$ko" || return 1
	loaded=$(cat "/sys/module/$MODULE/srcversion" 2>/dev/null) || return 0
	[ "$loaded" = "$(modinfo -F srcversion "$MODULE" 2>/dev/null)" ]
}

module_refuses || {
	ktap_skip "crypto/acompress_close: the $MODULE that would run lacks the refusal, and one without it wedges the runtime here"
	ktap_totals
	exit 0
}

mark_dmesg
output=$(${CLI:-lunatik} run "$SCRIPT" 2>&1)
case "$output" in
"")
	ktap_pass "crypto/acompress_close" ;;
*"the kernel serves no lz4"*|*"completes asynchronously"*)
	ktap_skip "crypto/acompress_close: $output" ;;
*)
	comment "$output"
	ktap_fail "crypto/acompress_close" ;;
esac
RESULT=0
check_dmesg || RESULT=1
ktap_totals || RESULT=1
exit $RESULT

