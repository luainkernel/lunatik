#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Concurrency test: verifies rcu.map() is safe when called while another
# kthread simultaneously modifies the table.
#
# Usage: sudo bash tests/rcu/map_sync.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SLEEP=5

cleanup() {
	lunatik stop tests/rcu/map_sync_clean 2>/dev/null
	lunatik stop tests/rcu/map_sync       2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
echo "# spawning map_sync (reader) and map_sync_clean (writer) kthreads..."
lunatik spawn tests/rcu/map_sync
echo "# running concurrently for ${SLEEP}s (timestamps from reader appear in dmesg)..."
sleep $SLEEP
echo "# stopping kthreads..."
cleanup

if check_dmesg; then
	ktap_pass "rcu/map_sync"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

