#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the darken tests and reports aggregated KTAP results.
#
# context: darken.run allocates its transform with crypto_alloc_skcipher, which
# allocates with GFP_KERNEL and may load a module, so a hook of an
# interrupt-context runtime that calls it would sleep under the runtime's
# spinlock. context.lua creates a runtime in each context whose body, which runs
# in process context, decrypts and runs a chunk, and resumes it past the body:
# a process runtime runs the chunk again, and a softirq and a hardirq runtime,
# armed as a hook finds them, each refuse with the message the case asserts. A
# build without the refusal allocates the transform under the spinlock, so the
# case skips unless the loaded luadarken is the installed one and that file
# carries the refusal, which is inline and has no symbol of its own.
#
# Usage: sudo bash tests/darken/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT="tests/darken/context"
MODULE="luadarken"
REFUSAL="not allowed after module load"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if ! [ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] ||
	! grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"; then
	ktap_skip "darken/context: the loaded $MODULE does not carry the refusal: it would allocate under a spinlock"
elif run_test "$SCRIPT"; then
	ktap_pass "darken/context"
else
	ktap_fail "darken/context"
fi

ktap_totals

