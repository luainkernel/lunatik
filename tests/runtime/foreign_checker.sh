#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the checker matrix: a method of every class a process
# runtime can construct (data, fifo, completion, set, crypto_shash, task,
# runtime), called through the class's metatable, refuses an object of another
# class naming both classes, which proves the metatables carry __name, refuses
# nil and a userdata of another library (io's) as no object at all; rcu.map
# refuses nil the same way; and a method on a closed runtime or fifo, whose
# private is gone, is refused instead of dereferencing NULL.
#
# Usage: sudo bash tests/runtime/foreign_checker.sh

SCRIPT="tests/runtime/foreign_checker"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "every checker refuses another class, nil, a foreign userdata and a closed object"

ktap_totals

