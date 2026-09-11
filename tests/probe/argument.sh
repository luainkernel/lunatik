#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Covers the argument closure a probe handler receives, on the three outcomes it
# has: a read that succeeds, an index it must reject, and a call once the handler
# returned.
#
# The probe is on vfs_read(file, buf, count, pos), so argument(2) is the byte count
# the caller asked for. The shell reads exactly COUNT bytes from /dev/zero, a size
# nothing else on the host is likely to ask for, and the script reports only when it
# sees that size: another reader cannot make the case pass for the wrong reason. On
# that same call it also checks that a negative index raises, then keeps the closure
# for the next call to prove it raises once the handler that received it returned.
#
# Usage: sudo bash tests/probe/argument.sh

SCRIPT="tests/probe/argument"
COUNT=8191 # must match COUNT in argument.lua

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

CONFIG="/boot/config-$(uname -r)"
if [ -r "$CONFIG" ] && ! grep -q '^CONFIG_HAVE_FUNCTION_ARG_ACCESS_API=y' "$CONFIG"; then
	for what in "reads the n-th argument" "rejects a negative index" "raises once the handler returned"; do
		ktap_skip "argument: $what needs CONFIG_HAVE_FUNCTION_ARG_ACCESS_API"
	done
	ktap_totals
	exit 0
fi

mark_dmesg
run_script "$SCRIPT" hardirq
dd if=/dev/zero of=/dev/null bs=$COUNT count=1 > /dev/null 2>&1
dd if=/dev/zero of=/dev/null bs=512 count=1 > /dev/null 2>&1
sleep 1
lunatik stop "$SCRIPT" > /dev/null 2>&1
check_dmesg || { ktap_totals; exit 1; }

reported() { dmesg_since | grep -qF "probe argument: $1"; }

reported read || fail "argument(2) never returned the size the reader asked for"
ktap_pass "argument(n) reads the n-th argument of the probed function"

reported bounds || fail "argument(-1) did not raise"
ktap_pass "argument(n) rejects an index below zero"

reported stale || fail "argument() did not raise after the handler that received it returned"
ktap_pass "argument() raises once its handler returned"

ktap_totals

