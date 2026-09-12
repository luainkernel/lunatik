#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Covers the refusal a probe handler gets from the three entry points that sleep.
# register_kprobe takes kprobe_mutex, cpus_read_lock and text_mutex;
# unregister_kprobe takes kprobe_mutex and waits on synchronize_rcu; enable_kprobe
# and disable_kprobe take kprobe_mutex. A probe script runs in a hardirq runtime,
# which is process context only while its body loads, so from a handler all three
# must be refused.
#
# The script exercises the other half first: while it loads, in process context,
# it registers a probe, disables and re-enables it and stops it. Then it probes
# vfs_read and, on its first hit, calls probe.new, stop and enable from the
# handler, reporting each one the runtime refuses.
#
# Do not run this against a build without lunatik_checkarmed: unregister_kprobe
# would reach synchronize_rcu with interrupts off and hang the machine. That is
# also why the guard itself is not proven by removing it; what is proven below is
# that the assertions read what they claim.
#
# Usage: sudo bash tests/probe/armed.sh

SCRIPT="tests/probe/armed"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT" hardirq
dd if=/dev/zero of=/dev/null bs=512 count=1 > /dev/null 2>&1
sleep 1
lunatik stop "$SCRIPT" > /dev/null 2>&1
check_dmesg || { ktap_totals; exit 1; }

reported() { dmesg_since | grep -qF "probe $1"; }

reported "loading: new, enable and stop" || fail "an entry point was refused while the script loaded"
ktap_pass "new, enable and stop are allowed while the script loads, in process context"

reported "armed: new" || fail "probe.new from a handler was not refused"
ktap_pass "probe.new is refused from a handler, where register_kprobe would sleep"

reported "armed: stop" || fail "stop from a handler was not refused"
ktap_pass "stop is refused from a handler, where unregister_kprobe would sleep"

reported "armed: enable" || fail "enable from a handler was not refused"
ktap_pass "enable is refused from a handler, where enable_kprobe would sleep"

ktap_totals

