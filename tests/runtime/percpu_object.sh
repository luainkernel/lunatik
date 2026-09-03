#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the percpu object: lunatik.percpu() runs the script once per
# possible CPU id, each instance seeing its own id; stop closes every instance and
# the object can be created again; stop refuses an object of another class; and a
# script that fails on one instance raises with its error instead of returning an object.
#
# Usage: sudo bash tests/runtime/percpu_object.sh

SCRIPT="tests/runtime/percpu_object"

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
ktap_pass "lunatik.percpu runs the script per CPU id, stops, reruns, checks its class and rolls back"

ktap_totals

