#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all fsnotify tests.
#
# Usage: sudo bash tests/fsnotify/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
TESTS="open nomask child kinds mask marks inside identity overlap expired reentrancy thread lifetime context\
	allow deny default exec access error sleep"
FAILED=0

source "$DIR/../lib.sh"

# the module is built out only where the kernel lacks CONFIG_FSNOTIFY
if ! modinfo luafsnotify > /dev/null 2>&1; then
	ktap_header
	ktap_plan $(echo $TESTS | wc -w)
	for t in $TESTS; do
		ktap_skip "fsnotify/$t: luafsnotify not installed"
	done
	ktap_totals
	exit 0
fi

SEP=$'\n'
for t in $TESTS; do
	echo "${SEP}# --- $t.sh ---"
	bash "$DIR/$t.sh" || FAILED=$((FAILED+1))
done

exit $FAILED

