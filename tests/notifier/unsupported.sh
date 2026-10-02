#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# On a kernel built without CONFIG_VT, notifier.keyboard and notifier.vt raise
# EOPNOTSUPP, called from the hardirq runtime a script registers them from.
# Runs only on such a kernel, and skips on one with CONFIG_VT, which has a
# /sys/class/tty/tty0.
#
# Usage: sudo bash tests/notifier/unsupported.sh

SCRIPT="tests/notifier/unsupported"
VT="/sys/class/tty/tty0" # only vty_init, under CONFIG_VT, creates it
CASE="keyboard and vt raise EOPNOTSUPP without CONFIG_VT"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if [ -e "$VT" ]; then
	echo "# SKIP: kernel with CONFIG_VT"
	ktap_skip "$CASE"
elif run_test --context=hardirq "$SCRIPT"; then
	ktap_pass "$CASE"
else
	ktap_fail "$CASE"
fi

ktap_totals

