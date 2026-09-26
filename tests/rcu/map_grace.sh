#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# rcu.map() walks inside an SRCU read-side critical section, so an entry a
# writer removes while the callback runs stays allocated until the walk ends,
# however long the callback sleeps. map_grace walks a one-bucket table whose
# callback removes the other entries and sleeps past a grace period on the
# first visit: the walk ends with that one visit and dmesg carries no oops.
#
# Skips unless the loaded luarcu carries luarcu_freeentry, the SRCU callback,
# since on a module without it the walk resumes from an entry freed under it.
#
# Usage: sudo bash tests/rcu/map_grace.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT="tests/rcu/map_grace"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if ! grep -qE ' luarcu_freeentry(\s|$)' /proc/kallsyms; then
	ktap_skip "rcu/map_grace: the loaded luarcu has no luarcu_freeentry"
	ktap_totals
	exit 0
fi

if run_test "$SCRIPT"; then
	ktap_pass "rcu/map_grace"
else
	ktap_fail "rcu/map_grace"
fi

ktap_totals

