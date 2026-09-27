#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for a library opened in a state that already has its
# classes: the _ENV object every runtime receives is an rcu.table, whose clone
# creates the class metatables without opening luarcu or adding rcu.table to
# package.loaded, and the script's own require("rcu") opens the library
# afterwards. The open must keep the metatables the clone created, so an object
# cloned before it and one made after share their metatable.
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
ktap_pass "a library opened after a clone of its class keeps the class metatables"

ktap_totals

