#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the percpu object: lunatik.percpu() runs the script once per
# possible CPU id, each runtime seeing its own id; stop closes every runtime and
# the object can be created again; and stop refuses an object of another class,
# a runtime, naming lunatik.percpu and lunatik.runtime.
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
ktap_pass "lunatik.percpu runs the script per CPU id, stops, reruns and checks its class"

ktap_totals

