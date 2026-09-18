#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that the upcall refuses a runtime that may not sleep: it takes a mutex
# and waits on a completion, so a softirq runtime is told so at the call rather
# than deadlocking later. lunatik_checkruntime compares the runtime's own
# context, not the one the call happens to run in, so the refusal fires from
# the script body even though that body runs in process context.
#
# context.lua calls handshake.client with no socket at all, which is what makes
# the case discriminate: the runtime check is the first statement of the
# binding, so a runtime that may not sleep never reaches the argument check and
# the message is "runtime context mismatch"; without that check the same call
# would answer "bad argument #1". A socket cannot stand in for the argument
# either, since its class is process-context and socket.new refuses the same
# runtime one line earlier.
#
# The context is chosen on the lunatik run command line, so this is a script of
# its own rather than a case inside another.
#
# Usage: sudo bash tests/handshake/context.sh

SCRIPT="tests/handshake/context"
MODULE="luahandshake"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "context: a softirq runtime is refused"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"

mark_dmesg
out=$(lunatik run "$SCRIPT" softirq 2>&1)
cleanup
check_dmesg || { ktap_totals; exit 1; }

echo "$out" | grep -qF "runtime context mismatch" ||
	fail "expected 'runtime context mismatch' from a softirq runtime"
ktap_pass "context: a softirq runtime is refused"

ktap_totals

