#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Concurrency test: verifies rcu.foreach() is safe when called while another
# kthread simultaneously modifies the table.
#
# Usage: sudo bash tests/rcu/foreach_sync.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SLEEP=5

cleanup() {
	lunatik stop tests/rcu/foreach_sync_clean 2>/dev/null
	lunatik stop tests/rcu/foreach_sync       2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
echo "# spawning foreach_sync (reader) and foreach_sync_clean (writer) kthreads..."
lunatik spawn tests/rcu/foreach_sync
echo "# running concurrently for ${SLEEP}s (timestamps from reader appear in dmesg)..."
sleep $SLEEP
echo "# stopping kthreads..."
cleanup

if check_dmesg; then
	ktap_pass "rcu/foreach_sync"
fi

ktap_totals

