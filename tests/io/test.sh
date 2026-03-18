#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests for the io library: open, read, write, seek, lines, type, edge cases.
#
# Usage: sudo bash tests/io/test.sh

SCRIPT="tests/io/test"
TMPFILE="/tmp/lunatik_io_test"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	rm -f "$TMPFILE"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

ktap_pass "io: open/read/write/seek/lines/type and edge cases"

ktap_totals

