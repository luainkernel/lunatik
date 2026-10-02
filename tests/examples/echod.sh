#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Drives the spawned examples/echod/daemon past 256 connections from the shell, in
# rounds of clients that connect at once, so the daemon accepts the connections of a
# round back to back while the workers it started for the ones before may not have
# read their number yet. Every client must get its line back, and the workers must
# log the numbers 1 to the last client's once each: a number the daemon kept in a
# byte stops at 255, and one it shared among the workers can be read twice in a round.
#
# Usage: sudo bash tests/examples/echod.sh

EXAMPLE="examples/echod/daemon"
MODULE="luasocket"
PORT=1337
ROUNDS=10
BURST=32
TIMEOUT=5
CLIENTS=$((ROUNDS * BURST))
DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

cleanup() {
	lunatik stop "$EXAMPLE" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

client() {
	timeout "$TIMEOUT" bash -c 'exec 3<> "/dev/tcp/127.0.0.1/$1" && echo "client $2" >&3 &&
		IFS= read -r line <&3 && [ "$line" = "client $2" ]' _ "$PORT" "$1"
}

ktap_header
ktap_plan 2

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
spawned=$(lunatik spawn "$EXAMPLE" 2>&1)
[ -z "$spawned" ] || { comment "$spawned"; fail "$EXAMPLE did not spawn"; }

echoed=0
for round in $(seq 0 $((ROUNDS - 1))); do
	pids=()
	for i in $(seq $((round * BURST + 1)) $(((round + 1) * BURST))); do
		client "$i" &
		pids+=($!)
	done
	for pid in "${pids[@]}"; do
		wait "$pid" && echoed=$((echoed + 1))
	done
done
cleanup

numbers=$(dmesg_since | sed -n 's/.*echod \[worker #\([0-9]*\)\]: started$/\1/p' | sort -n)

if [ "$numbers" != "$(seq 1 "$CLIENTS")" ]; then
	comment "$(echo "$numbers" | grep -c .) workers started, highest number $(echo "$numbers" | tail -1)"
	comment "numbers logged twice: [$(echo "$numbers" | uniq -d | tr '\n' ' ')]"
	fail "the workers did not log the numbers 1 to $CLIENTS once each"
fi
ktap_pass "echod: the workers log the numbers 1 to $CLIENTS once each"

[ "$echoed" -eq "$CLIENTS" ] || fail "$echoed of $CLIENTS clients got their line back"
ktap_pass "echod: each of $CLIENTS clients, $BURST at a time, gets its line back"

check_dmesg || { ktap_totals; exit 1; }

ktap_totals

