#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all crypto tests and reports aggregated KTAP results.
#
# shash, skcipher, aead, rng, sig, kpp, hkdf, comp, quic and hardirq allocate each algorithm their cases use before
# the first of them, through tests/lib.lua's alloc, and skip where the kernel serves one not at all, which the script
# names. rng skips where the kernel's configuration has no CONFIG_CRYPTO_RNG2, without which crypto.rng raises
# EOPNOTSUPP, and fails where it has the option and crypto.rng raises it.
#
# quic: a softirq runtime's body creates hmac(sha256), through crypto.hkdf, ecb(aes) and ctr(aes), and its hook,
# resumed with RFC 9001 A.2's protected client Initial, derives A.1's client keys from the packet's connection ID,
# removes the header protection and deciphers the payload with ctr(aes) from GCM's second counter, its tag unchecked.
#
# hardirq: crypto.shash and crypto.skcipher refuse a hardirq runtime in its body and past it, and the methods of an
# object handed over there refuse it, since its callbacks run with IRQs disabled.
#
# context: a crypto object refused for its execution context leaves nothing
# allocated, measured on the reference a tfm holds on the module implementing
# the algorithm, for shash, skcipher, comp and sig.
#
# async: skcipher and aead refuse an asynchronous implementation, cryptd's.
#
# large: skcipher, aead and comp take a copy of their input in one kmalloc block, and refuse one
# past KMALLOC_MAX_SIZE, the size past which a string is always vmalloc memory.
#
# deferred: comp waits for an asynchronous implementation, a module the test builds whose worker
# completes each request after the call returned, through the backlog for decompress.
#
# seed: rng and reset without a seed seed an algorithm with seedsize() random bytes, ansi_cprng's 48.
#
# sig: crypto.sig verifies the kernel's own ECDSA P-256 vector and an RSA PKCS#1 v1.5 pair openssl
# signed, each verifier allocated by its 6.13 name and, on ENOENT, by the name of 6.12 and earlier.
#
# kpp: crypto.kpp agrees ECDH secrets the kernel's P-256 vector gives and two generated keys agree on,
# opens a secret an ephemeral key wrapped for a key generated in the kernel through hkdf and gcm(aes),
# answers nil and EINVAL for a peer's key the curve refuses on P-256 and P-384, which only the binding's check
# answers, a driver's own refusal raising, and refuses a private key of another length, out of range, or for
# another key agreement. crypto.kpp is nil where the kernel has no ECDH, and the
# script then raises as for an algorithm the kernel does not serve; where the kernel serves
# ecdh-nist-p256, which /proc/crypto lists once crypto-ecdh loads, that raise is a binding that was not
# built, and the case fails.
#
# Usage: sudo bash tests/crypto/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="shash skcipher aead rng sig kpp hkdf quic hardirq comp"
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

# the kernel's config, where it can be read, builds ECDH, and /proc/crypto lists the curve once its module loads
ecdh_served() {
	lacks CONFIG_CRYPTO_ECDH && return 1
	modprobe -q crypto-ecdh
	grep -qE '^name[[:space:]]+: ecdh-nist-p256$' /proc/crypto
}

for t in $TESTS; do
	if [ "$t" = rng ] && lacks CONFIG_CRYPTO_RNG2; then
		ktap_skip "crypto/rng: needs CONFIG_CRYPTO_RNG2"
	elif [ "$t" = kpp ] && ecdh_served; then
		if output=$(run_test "tests/crypto/$t"); then
			ktap_pass "crypto/$t"
		else
			[ -n "$output" ] && echo "$output"
			ktap_fail "crypto/$t"
		fi
	else
		served_case "crypto/$t" run_test "tests/crypto/$t"
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
bash "$DIR/deferred.sh" || RESULT=1
echo ""
bash "$DIR/seed.sh" || RESULT=1
echo ""
bash "$DIR/sig_refused.sh" || RESULT=1
exit $RESULT

