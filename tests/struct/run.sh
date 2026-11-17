#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests for the struct library: format derivation from a layout descriptor
# (inter-field padding, signed fields, trailing pad, out-of-order fields),
# the codec's fields in offset order, the pack/unpack round-trip, and the
# overlapping-fields (union) guard.
#
# A codec's view over a data object, at a base past the first bytes, reads every field of every
# width and sign as unpack reads it off the same bytes, two fields named as what the view is
# handed, data and at, included. A field past the end of the data raises "out of bounds" while one
# before it reads, an assignment raises "struct: a view is read-only" and leaves what the field
# reads, and a name the layout lacks raises.
#
# Usage: sudo bash tests/struct/test.sh

SCRIPT="tests/struct/test"
VIEW="tests/struct/view"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$VIEW" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "struct: format derivation, round-trip and overlap guard"

if run_test "$VIEW"; then
	ktap_pass "struct: a view reads each field in place, by name"
else
	ktap_fail "struct: a view reads each field in place, by name"
fi

ktap_totals

