#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Holds the vendored Lua to the contract the README documents, which the kernel
# patch produces and no other suite asserts: a lost guard compiles and the rest
# of the suite stays green, so a bump of lua/ is read against these.
#
# floats:      no float literal, no '^', integer '/', no libm, no float
#              conversion in string.format or string.pack.
# identifiers: _VERSION, collectgarbage("count") in bytes, package.path, and
#              the entry points a module cannot carry.
#
# Usage: sudo bash tests/language/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="floats identifiers"
TOTAL=$(echo $TESTS | wc -w)

cleanup()
{
	for t in $TESTS; do
		lunatik stop "tests/language/$t" > /dev/null 2>&1
	done
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/language/$t"; then
		ktap_pass "language/$t"
	else
		ktap_fail "language/$t"
	fi
done

ktap_totals
[ $KTAP_FAIL -eq 0 ]

