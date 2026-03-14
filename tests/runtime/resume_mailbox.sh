#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test: completion objects must be passable via runtime:resume()
# to enable the mailbox pattern. Passes a fifo and completion to a sub-runtime
# that sends a message; the main runtime receives and asserts the value.
#
# Usage: sudo bash tests/runtime/resume_mailbox.sh

SCRIPT="tests/runtime/resume_mailbox"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

for mod in luafifo luacompletion; do
	cat /sys/module/$mod/refcnt > /dev/null 2>&1 || {
		echo "# SKIP: $mod not loaded"
		ktap_totals
		exit 0
	}
done

mark_dmesg

lunatik run "$SCRIPT"

check_dmesg || { ktap_totals; exit 1; }
ktap_pass "mailbox send/receive via resume succeeded"

ktap_totals

