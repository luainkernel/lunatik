#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the class check in methods that read private as their own
# type: device:stop, notifier:stop, probe:stop, probe:enable and the rcu.table
# index and newindex metamethods, each called on a data object through the
# class's metatable, must be refused instead of reading the buffer as the class.
# The probe methods run in their own hardirq script, the context probe.new requires.
#
# Usage: sudo bash tests/runtime/foreign_method.sh

SCRIPT="tests/runtime/foreign_method"
PROBE="tests/runtime/foreign_method_probe"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$PROBE" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "the methods of device, notifier and rcu.table refuse an object of another class"

mark_dmesg
run_script "$PROBE" hardirq
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$PROBE" > /dev/null 2>&1
ktap_pass "the probe methods refuse an object of another class"

ktap_totals

