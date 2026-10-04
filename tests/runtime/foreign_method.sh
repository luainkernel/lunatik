#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the class check in methods that read private as their own
# type: device:stop, notifier:stop, probe:stop, probe:enable, probe:disable and the
# rcu.table index and newindex metamethods, each called on a data object through
# the class's metatable, must be refused instead of reading the buffer as the class;
# netlink.channel:stop, which closes the object it is given, must be refused
# instead of closing the buffer.
# The probe methods run in their own hardirq script, the context probe.new requires,
# and notifier:stop in its own softirq script, the context notifier.netdevice requires.
#
# Usage: sudo bash tests/runtime/foreign_method.sh

SCRIPT="tests/runtime/foreign_method"
PROBE="tests/runtime/foreign_method_probe"
NOTIFIER="tests/runtime/foreign_method_notifier"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$PROBE" > /dev/null 2>&1
	lunatik stop "$NOTIFIER" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "the methods of device, netlink.channel and rcu.table refuse an object of another class"

mark_dmesg
run_script --context=hardirq "$PROBE"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$PROBE" > /dev/null 2>&1
ktap_pass "the probe methods refuse an object of another class"

mark_dmesg
run_script --context=softirq "$NOTIFIER"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$NOTIFIER" > /dev/null 2>&1
ktap_pass "notifier:stop refuses an object of another class"

ktap_totals

