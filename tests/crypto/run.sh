#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all crypto tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/crypto/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="shash skcipher aead rng hkdf comp"
TOTAL=$(echo $TESTS | wc -w)

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	mark_dmesg
	if ! lunatik run "tests/crypto/$t" 2>/dev/null; then
		ktap_fail "crypto/$t: script execution failed"
		continue
	fi
	errs=$(dmesg_since | grep -iE "^[^:]+: FAIL	|\.lua:[0-9]+:" || true)
	if [ -z "$errs" ]; then
		ktap_pass "crypto/$t"
	else
		ktap_fail "crypto/$t"
		while IFS= read -r line; do
			echo "# $line"
		done <<< "$errs"
	fi
done

ktap_totals
[ $KTAP_FAIL -eq 0 ]

