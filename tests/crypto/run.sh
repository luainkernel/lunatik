#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all crypto tests and reports aggregated KTAP results.
#
# shash, skcipher, aead, rng, sig and hkdf allocate each algorithm their cases use before the first of them, through
# tests/lib.lua's alloc, and skip where the kernel serves one not at all, which the script names.
#
# context: a crypto object refused for its execution context leaves nothing
# allocated, measured on the reference a tfm holds on the module implementing
# the algorithm, for the two constructors that allocated one before the object.
#
# async: skcipher and aead refuse an asynchronous implementation, cryptd's.
#
# large: skcipher, aead and comp take a copy of their input in one kmalloc block, and refuse one
# past KMALLOC_MAX_SIZE, the size past which a string is always vmalloc memory.
#
# seed: rng and reset without a seed seed an algorithm with seedsize() random bytes, ansi_cprng's 48.
#
# sig: crypto.sig verifies the kernel's own ECDSA P-256 vector and an RSA PKCS#1 v1.5 pair openssl
# signed, each verifier allocated by its 6.13 name and, on ENOENT, by the name of 6.12 and earlier.
#
# Usage: sudo bash tests/crypto/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="shash skcipher aead rng sig hkdf comp"
TOTAL=$(echo $TESTS | wc -w)

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/crypto/$t" 2>/dev/null
	done
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	served_case "crypto/$t" run_test "tests/crypto/$t"
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
echo ""
bash "$DIR/sig_refused.sh" || RESULT=1
exit $RESULT

