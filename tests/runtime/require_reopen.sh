#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for a library opened twice in one state: the _ENV object
# every runtime receives registers luarcu under its class name, rcu.table,
# and the script's own require("rcu") opens it again under the module name.
# The second open must keep the class metatables the first created, so an
# object made before it and one made after share their metatable.
#
# Usage: sudo bash tests/runtime/require_reopen.sh

SCRIPT="tests/runtime/require_reopen"

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
ktap_pass "a library opened again under another name keeps its classes"

ktap_totals

