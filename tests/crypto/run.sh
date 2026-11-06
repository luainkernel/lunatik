#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all crypto tests and reports aggregated KTAP results.
#
# shash, skcipher, aead, rng, sig, hkdf, comp, compress and acompress allocate each algorithm their cases use
# before the first of them, through tests/lib.lua's alloc, and skip where the kernel serves one not at all, which
# the script names.
#
# context: a crypto object refused for its execution context leaves nothing
# allocated, measured on the reference a tfm holds on the module implementing
# the algorithm, for the three constructors that allocated one before the object.
#
# async: skcipher and aead refuse an asynchronous implementation, cryptd's.
#
# large: skcipher, aead and acompress copy their input into one kmalloc block, and refuse one past
# KMALLOC_MAX_SIZE, the size past which a string is always vmalloc memory.
#
# seed: rng and reset without a seed seed an algorithm with seedsize() random bytes, ansi_cprng's 48.
#
# sig: crypto.sig verifies the kernel's own ECDSA P-256 vector and an RSA PKCS#1 v1.5 pair openssl
# signed, each verifier allocated by its 6.13 name and, on ENOENT, by the name of 6.12 and earlier.
#
# comp passes through lib/crypto/comp.lua: the native binding before 6.15, crypto.compress over
# acompress where the kernel removed the crypto_comp API; compress is that wrapper, and acompress
# the asynchronous class under both.
#
# comp_native: the native crypto.comp refuses an object of another class. lib/luacrypto_comp.c compiles
# to nothing from 6.15 on, by its version guard, so the case is skipped there on the same version.
#
# acompress_callback: a compression's callback submits the decompression of its output, and a
# callback that raises leaves its request usable. An asynchronous driver runs those callbacks only
# once the script body has returned, so the case reads its lines from dmesg.
#
# Usage: sudo bash tests/crypto/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="shash skcipher aead rng sig hkdf comp compress acompress"
TOTAL=$(($(echo $TESTS | wc -w) + 1))

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/crypto/$t" 2>/dev/null
	done
	lunatik stop "tests/crypto/comp_native" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	served_case "crypto/$t" run_test "tests/crypto/$t"
done

if [ "$(printf '%s\n' 6.15 "$(uname -r)" | sort -V | head -n 1)" = 6.15 ]; then
	ktap_skip "crypto/comp_native: the binding has no crypto.comp from 6.15 on"
else
	served_case "crypto/comp_native" run_test "tests/crypto/comp_native"
fi

RESULT=0
ktap_totals || RESULT=1

echo ""
bash "$DIR/context.sh" || RESULT=1
echo ""
bash "$DIR/async.sh" || RESULT=1
echo ""
bash "$DIR/large.sh" || RESULT=1
echo ""
bash "$DIR/acompress_callback.sh" || RESULT=1
echo ""
bash "$DIR/seed.sh" || RESULT=1
echo ""
bash "$DIR/sig_refused.sh" || RESULT=1
exit $RESULT

