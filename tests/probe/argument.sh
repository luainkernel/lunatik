#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Covers the probe.regs a probe handler receives: argument reads the n-th argument
# of the probed function and rejects an index it cannot use, dump prints the
# registers of the hit, both refuse an object of another class, the object cannot
# be shared with another runtime, every hit of the runtime receives the same object,
# and that object stops reaching the registers once no handler runs, a hit that finds
# no handler included.
#
# The probe is on vfs_read(file, buf, count, pos), so argument(2) is the byte count
# the caller asked for. The shell reads exactly COUNT bytes from /dev/zero, a size
# nothing else on the host is likely to ask for, and the script reports only when it
# sees that size: another reader cannot make the case pass for the wrong reason. On
# that same call it also checks that a negative index and a data object raise and that
# an rcu.table refuses the object, dumps the registers, whose task line names dd, and
# keeps the object for the next call to compare with the one it receives. That next
# call also takes the handler out of the table, so the hits left before the stop, the
# reads lunatik stop makes of its own script among them, find no handler and must leave
# the object cleared. Every hit hands its handler that same object, so it is read
# outside a handler by a finalizer at the stop: the close finalizes in reverse order
# of marking, and the finalizer marked after the object reads it whole. There
# argument(-1) must raise closed object before dump is called: argument checks the
# object before the index, so a build that stopped clearing the object raises out of
# bounds there without reading a register, and is reported instead of reading or
# dumping a pt_regs that is gone.
#
# Usage: sudo bash tests/probe/argument.sh

SCRIPT="tests/probe/argument"
COUNT=8191 # must match COUNT in argument.lua

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 7

CONFIG="/boot/config-$(uname -r)"
if [ -r "$CONFIG" ] && ! grep -q '^CONFIG_HAVE_FUNCTION_ARG_ACCESS_API=y' "$CONFIG"; then
	for what in "reads the n-th argument" "rejects a negative index" "prints the registers" \
		"refuses another class" "cannot be shared" "is one object per runtime" \
		"goes stale outside a handler"; do
		ktap_skip "regs: $what needs CONFIG_HAVE_FUNCTION_ARG_ACCESS_API"
	done
	ktap_totals
	exit 0
fi

mark_dmesg
run_script --context=hardirq "$SCRIPT"
dd if=/dev/zero of=/dev/null bs=$COUNT count=1 > /dev/null 2>&1
dd if=/dev/zero of=/dev/null bs=512 count=1 > /dev/null 2>&1
sleep 1
lunatik stop "$SCRIPT" > /dev/null 2>&1
check_dmesg || { ktap_totals; exit 1; }

reported() { dmesg_since | grep -qF "probe argument: $1"; }

reported read || fail "regs:argument(2) never returned the size the reader asked for"
ktap_pass "regs:argument(n) reads the n-th argument of the probed function"

reported bounds || fail "regs:argument(-1) did not raise"
ktap_pass "regs:argument(n) rejects an index below zero"

dmesg_since | grep -qF "Comm: dd " || fail "regs:dump() printed no task line for the reader"
ktap_pass "regs:dump() prints the registers of the hit"

reported foreign || fail "a regs method accepted a data object"
ktap_pass "the regs methods refuse an object of another class"

reported single || fail "an rcu.table took the regs, which another runtime could read"
ktap_pass "regs cannot be shared with another runtime"

reported shared || fail "the next hit received another regs object"
ktap_pass "every hit of the runtime receives the same regs"

reported stale || fail "the regs still reached the registers once no handler ran"
ktap_pass "regs raises closed object outside a handler, after hits that found none"

ktap_totals

