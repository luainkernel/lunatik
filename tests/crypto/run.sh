#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all crypto tests and reports aggregated KTAP results.
#
# context: a crypto object refused for its execution context leaves nothing
# allocated, measured on the reference a tfm holds on the module implementing
# the algorithm, for the two constructors that allocated one before the object.
#
# async: skcipher and aead refuse an asynchronous implementation, cryptd's.
#
# large: skcipher and aead cipher a copy of their input in one kmalloc block, and refuse one past
# KMALLOC_MAX_SIZE, the size past which a string is always vmalloc memory.
#
# seed: rng and reset without a seed seed an algorithm with seedsize() random bytes, ansi_cprng's 48.
#
# sig: crypto.sig verifies the kernel's own ECDSA P-256 vector and an RSA PKCS#1 v1.5 pair openssl
# signed, each verifier allocated by its 6.13 name and, on ENOENT, by the name of 6.12 and earlier.
# It skips where the kernel builds no ECDSA or no RSA.
#
# comp is served only where the kernel still has the crypto_comp API, which
# Linux 6.15 removed: lib/luacrypto_comp.c compiles to nothing there and
# crypto.comp is nil. hascomp asks the runtime for the binding, so the suite
# skips that test instead of failing every case in it.
#
# Usage: sudo bash tests/crypto/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="shash skcipher aead rng sig hkdf comp"
TOTAL=$(echo $TESTS | wc -w)
PROBE="tests/crypto/hascomp"

CONFIG=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)

hassig() {
	grep -q '^CONFIG_CRYPTO_ECDSA=' <<< "$CONFIG" && grep -q '^CONFIG_CRYPTO_RSA=' <<< "$CONFIG"
}

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/crypto/$t" 2>/dev/null
	done
	lunatik stop "$PROBE" 2>/dev/null
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
	elif [ "$t" = sig ] && [ -n "$CONFIG" ] && ! hassig; then
		ktap_skip "crypto/$t: needs CONFIG_CRYPTO_ECDSA and CONFIG_CRYPTO_RSA"
	elif run_test "tests/crypto/$t"; then
		ktap_pass "crypto/$t"
	else
		ktap_fail "crypto/$t"
	fi
done

RESULT=0
ktap_totals || RESULT=1

echo ""
bash "$DIR/context.sh" || RESULT=1
echo ""
bash "$DIR/async.sh" || RESULT=1
echo ""
bash "$DIR/large.sh" || RESULT=1
echo ""
bash "$DIR/seed.sh" || RESULT=1
exit $RESULT

