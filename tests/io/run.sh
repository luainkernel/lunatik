#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests for the io library: open, read, write, seek, lines, type, edge cases, and its absence
# from softirq and hardirq runtimes, which open every library but io.
#
# Usage: sudo bash tests/io/run.sh

SCRIPT="tests/io/test"
SCRIPT_IRQ="tests/io/irq"
TMPFILE="/tmp/lunatik_io_test"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$SCRIPT_IRQ" 2>/dev/null
	rm -f "$TMPFILE"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

ktap_pass "io: open/read/write/seek/lines/type and edge cases"

mark_dmesg
run_script --context=softirq "$SCRIPT_IRQ"
lunatik stop "$SCRIPT_IRQ"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "io: not available in softirq runtime"

mark_dmesg
run_script --context=hardirq "$SCRIPT_IRQ"
lunatik stop "$SCRIPT_IRQ"
check_dmesg || { ktap_totals; exit 1; }
ktap_pass "io: not available in hardirq runtime"

ktap_totals

