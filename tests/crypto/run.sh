#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all crypto tests and reports aggregated KTAP results.
#
# comp is served only where the kernel still has the crypto_comp API, which
# Linux 6.15 removed: lib/luacrypto_comp.c compiles to nothing there and
# crypto.comp is nil. hascomp asks the runtime for the binding, so the suite
# skips that test instead of failing every case in it.
#
# Usage: sudo bash tests/crypto/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="shash skcipher aead rng hkdf comp"
TOTAL=$(echo $TESTS | wc -w)
PROBE="tests/crypto/hascomp"

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/crypto/$t" > /dev/null 2>&1
	done
	lunatik stop "$PROBE" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

probe=$(lunatik run "$PROBE" 2>&1)
case "$probe" in
	"") ;;
	*"crypto.comp is not built"*) MISSING=comp ;;
	*) comment "$probe"; fail "the comp probe did not run" ;;
esac

for t in $TESTS; do
	if [ "$t" = "$MISSING" ]; then
		ktap_skip "crypto/$t: the binding is not built on this kernel"
	elif run_test "tests/crypto/$t"; then
		ktap_pass "crypto/$t"
	else
		ktap_fail "crypto/$t"
	fi
done

ktap_totals
[ $KTAP_FAIL -eq 0 ]

