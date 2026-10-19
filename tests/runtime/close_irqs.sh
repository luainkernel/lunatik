#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# lunatik_closeobject, the close and __close of every class that takes it,
# refuses a call made with IRQs disabled and closes everywhere else, read here
# on a fifo, an interrupt-context class whose close it is.
#
# runtime/close_irqs/softirq: a softirq runtime resumed past its body, the
# state a netfilter or XDP hook calls from, runs with bottom halves off and IRQs
# on, and there a fifo's close and the end of the scope of a to-be-closed
# variable holding another fifo close both, which the process runtime that
# resumed it reads from a push raising "closed object". A refusal keyed on the
# runtime's context or on atomic context, rather than on IRQs, raises in the
# callback and fails the case.
#
# runtime/close_irqs/probe: the body of a hardirq runtime, which runs with IRQs
# on, closes a fifo both ways, and the pre handler of a kprobe on the
# personality syscall, which setarch makes, sees a fifo's close and the end of
# the scope of a to-be-closed variable holding it raise "not allowed with IRQs
# disabled", and then pushes into the fifo, which the refusals left open: a
# hardirq runtime takes its lock with spin_lock_irqsave for every callback. The
# fifo's buffer is kmalloc'd, so a module without the refusal closes it in the
# handler and fails the case, as does one that refuses after the release.
# Skips without CONFIG_KPROBES or setarch.
#
# Usage: sudo bash tests/runtime/close_irqs.sh

SCRIPT="tests/runtime/close_irqs"
SCRIPT_PROBE="tests/runtime/close_irqs_probe"
PREFIX="close_irqs probe: "

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	for script in "$SCRIPT" "$SCRIPT_PROBE"; do
		lunatik stop "$script" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

if run_test "$SCRIPT"; then
	ktap_pass "runtime/close_irqs/softirq"
else
	ktap_fail "runtime/close_irqs/softirq"
fi

probe_refusal "runtime/close_irqs/probe" "$SCRIPT_PROBE" "$PREFIX"

ktap_totals

