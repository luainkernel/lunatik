#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what runtime:resume() returns to its caller.
#
# The sub-runtime yields one object, then two, then a value that is not an
# object, then a SINGLE one, and finally returns an object. The driver asserts
# it gets the objects back and in order; that the two refusals name their
# reason and leave the runtime suspended and resumable; and that a runtime
# whose body has returned is dead to the next resume. It also passes a number
# to resume(), which the inbound leg refuses the same way.
#
# The first resume carries two objects, which the sub-runtime checks it got in
# order: the values come back off the resumed stack, so an index taken from
# the caller's argument count lands on the wrong slot. One round carries more
# objects than the LUA_MINSTACK slots a C function is entered with, in both
# directions, which is a copy longer than the stack the copy is given.
#
# Usage: sudo bash tests/runtime/resume_results.sh

SCRIPT="tests/runtime/resume_results"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg

run_script "$SCRIPT"

check_dmesg || { ktap_totals; exit 1; }
ktap_pass "resume returns the objects the script yields and returns"

ktap_totals

