#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests for the io library: open, read, write, seek, lines, type, edge cases.
#
# Usage: sudo bash tests/io/test.sh

SCRIPT="tests/io/test"
SCRIPT_SOFTIRQ="tests/io/softirq"
TMPFILE="/tmp/lunatik_io_test"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	rm -f "$TMPFILE"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

ktap_pass "io: open/read/write/seek/lines/type and edge cases"

mark_dmesg
run_script "$SCRIPT_SOFTIRQ" softirq
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "io: not available in softirq runtime"

ktap_totals

