#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the signal tests and reports KTAP results.
#
# signal/kill: with a child sleeping in the background and a pid the shell has
# already reaped, kill(child, 0) finds the child and answers true,
# kill(reaped, 0) answers nil and ESRCH, a pid of 0, one past PID_MAX_LIMIT and
# one that would truncate to the child's, and a signal that would truncate to
# TERM, raise "out of bounds", and kill(child, TERM) answers true and signals
# the child, and the shell then sees the child end on SIGTERM.
# The truncation cases target the child on every build, so a module without
# the bound sends the child a signal and fails the case, never a stranger.
#
# The script runs from a CLI in a pid namespace of its own, which holds neither
# pid: kill reads a pid in the initial pid namespace, as task:pid() returns it,
# whichever task makes the call, and a module that reads it in the caller's
# answers ESRCH for the child and fails both cases. The shell has to run in the
# initial pid namespace, the only one whose pids are the ones kill reads, and
# the cases skip elsewhere or without pid namespaces.
#
# signal/softirq: a softirq runtime resumed past its body, the state a netfilter
# or XDP hook calls from, runs with bottom halves off and IRQs on, and there
# kill(1, 0) finds pid 1, where a refusal keyed on the context rather than on
# IRQs would raise.
#
# signal/probe: the body of a hardirq runtime, which runs with IRQs on, finds
# pid 1 with kill(1, 0), and the pre handler of a kprobe on the personality
# syscall, which setarch makes, sees the same call raise "not allowed with IRQs
# disabled": a hardirq runtime takes its lock with spin_lock_irqsave for every
# callback. Signal 0 never reaches the target's siglock, so a module without the
# refusal answers in the handler and fails the case rather than spinning on a
# siglock the CPU holds. Skips without CONFIG_KPROBES or setarch.
#
# Usage: sudo bash tests/signal/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
SCRIPT_KILL="tests/signal/kill"
SCRIPT_SOFTIRQ="tests/signal/softirq"
SCRIPT_PROBE="tests/signal/probe"
PIDMOD="/lib/modules/lua/tests/signal/pids.lua"
PREFIX="signal probe: "

source "$DIR/../lib.sh"

cleanup() {
	for script in "$SCRIPT_KILL" "$SCRIPT_SOFTIRQ" "$SCRIPT_PROBE"; do
		lunatik stop "$script" 2>/dev/null
	done
	rm -f "$PIDMOD"
	[ -n "${CHILD:-}" ] && kill -KILL "$CHILD" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

if run_test "$SCRIPT_SOFTIRQ"; then
	ktap_pass "signal/softirq"
else
	ktap_fail "signal/softirq"
fi

CONFIG=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)
if [ -n "$CONFIG" ] && ! grep -q '^CONFIG_KPROBES=y' <<< "$CONFIG"; then
	ktap_skip "signal/probe: needs CONFIG_KPROBES"
elif ! command -v setarch > /dev/null 2>&1; then
	ktap_skip "signal/probe: needs setarch"
elif run_test --context=hardirq "$SCRIPT_PROBE"; then
	setarch "$(uname -m)" -R true > /dev/null 2>&1
	lunatik stop "$SCRIPT_PROBE" 2>/dev/null
	refused=$(dmesg_since | grep -cF "${PREFIX}refused")
	answered=$(dmesg_since | grep -cF "${PREFIX}answered")
	errs=$(dmesg_since | grep -E "$KTAP_ERRORS")
	if [ "$refused" -ge 1 ] && [ "$answered" -eq 0 ] && [ -z "$errs" ]; then
		ktap_pass "signal/probe"
	else
		[ -n "$errs" ] && comment "$errs"
		ktap_fail "signal/probe: the handler's kill was refused $refused times and answered $answered times"
	fi
else
	ktap_fail "signal/probe"
fi

if ! initpidns || ! unshare --pid --fork true 2>/dev/null; then
	ktap_skip "signal/kill: needs to run in the initial pid namespace and to create another"
	ktap_skip "signal/kill: the child ends on SIGTERM"
	ktap_totals
	exit 0
fi

sleep 30 &
CHILD=$!
true &
REAPED=$!
wait "$REAPED"
echo "return {child = $CHILD, reaped = $REAPED}" > "$PIDMOD"

if CLI=pidns run_test "$SCRIPT_KILL"; then
	ktap_pass "signal/kill"
else
	ktap_fail "signal/kill"
fi

wait "$CHILD"
status=$?
CHILD=
if [ "$status" -eq 143 ]; then
	ktap_pass "signal/kill: the child ends on SIGTERM"
else
	ktap_fail "signal/kill: the child ended with status $status, not 143"
fi

ktap_totals

