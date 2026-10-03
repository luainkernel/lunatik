#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A thread holds its runtime until stop releases it, even once its body has
# returned, and the runtime that started the thread keeps it: dropping the
# handle releases nothing, and the end of that runtime releases it.
#
# release.lua is spawned, since thread.run is refused while a script loads. It
# threads a runtime whose handle it does not keep, with a body that leaves a
# sentinel whose finalizer completes a completion and logs when that runtime
# closes, and returns at once.
# Case 1: after the body returned and the driver collected its garbage, the
# runtime stays open, and the stop closes it. The stop reads the owner of the
# runtime's lock, so a runtime closed before it is a read of freed memory; a
# build that puts the runtime as the body returns closes it within the pause and
# fails there, before the stop. Case 2: a second thread whose handle the driver
# drops keeps its runtime open through a collect, and the driver's end, which
# lunatik stop brings, closes it: the runtimes log two closes. A build that does
# not keep the thread closes the second runtime as the collector releases the
# thread, and fails the pause.
#
# Usage: sudo bash tests/thread/release.sh

SCRIPT="tests/thread/release"
PREFIX="thread release test: "
SLEEP=2

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

reported()
{
	dmesg_since | grep -qF "$PREFIX$1"
}

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
sleep $SLEEP
lunatik stop "$SCRIPT"

reported "stopped" || fail "an exited thread did not hold its runtime until stop released it"
ktap_pass "an exited thread holds its runtime until stop releases it"

reported "kept" || fail "a dropped thread did not keep its runtime while the runtime that started it runs"
[ "$(dmesg_since | grep -cF "${PREFIX}closed")" = 2 ] || fail "the end of the runtime that started a thread did not release its runtime"
ktap_pass "a dropped thread keeps its runtime until the end of the runtime that started it"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

