#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Covers the closures a probe handler receives, on three outcomes: argument reads
# the n-th argument of the probed function, argument rejects an index it cannot
# use, and both argument and dump stop reaching the registers once the handler
# that received them returned.
#
# The probe is on vfs_read(file, buf, count, pos), so argument(2) is the byte count
# the caller asked for. The shell reads exactly COUNT bytes from /dev/zero, a size
# nothing else on the host is likely to ask for, and the script reports only when it
# sees that size: another reader cannot make the case pass for the wrong reason. On
# that same call it also checks that a negative index raises, then keeps both closures
# for the next call to prove the handler that received them no longer reaches the
# registers: argument raises, and dump is read through debug.getupvalue rather than
# called, so a build that stopped clearing it is reported instead of running show_regs
# on a pt_regs that is gone.
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
	for what in "reads the n-th argument" "rejects a negative index" "goes stale once the handler returned"; do
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

reported stale || fail "the closures still reached the registers after the handler that received them returned"
ktap_pass "the argument and dump closures go stale once their handler returned"

ktap_totals

