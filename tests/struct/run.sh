#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests for the struct library: format derivation from a layout descriptor
# (inter-field padding, signed fields, trailing pad, out-of-order fields),
# the pack/unpack round-trip, and the overlapping-fields (union) guard.
#
# Usage: sudo bash tests/struct/test.sh

SCRIPT="tests/struct/test"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 1

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "struct: format derivation, round-trip and overlap guard"

ktap_totals

