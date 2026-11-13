#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all crypto tests and reports aggregated KTAP results.
#
# shash, skcipher, aead, rng, sig, kpp, hkdf, comp, quic and hardirq allocate each algorithm their cases use before
# the first of them, through tests/lib.lua's alloc, and skip where the kernel serves one not at all, which the script
# names. Each skips where the kernel's configuration lacks the option of a class it reaches, CONFIG_CRYPTO_HASH2 for
# shash, CONFIG_CRYPTO_SKCIPHER2 for skcipher, CONFIG_CRYPTO_AEAD2 for aead, CONFIG_CRYPTO_RNG2 for rng,
# CONFIG_CRYPTO_SIG2 for sig and CONFIG_CRYPTO_ACOMP2 for comp, without which the class's constructor raises
# EOPNOTSUPP, and fails where it has the option and the constructor raises it.
#
# quic: a softirq runtime's body creates hmac(sha256), through crypto.hkdf, ecb(aes) and ctr(aes), and its hook,
# resumed with RFC 9001 A.2's protected client Initial, derives A.1's client keys from the packet's connection ID,
# removes the header protection and deciphers the payload with ctr(aes) from GCM's second counter, its tag unchecked.
# A second softirq runtime's body creates two hmac(sha256), and its hook keys both with RFC 9001's initial salt and
# hashes A.1's connection ID in two parts, through init, update and final, through finup, and through export into
# the second's import, to the digest of the whole, A.1's initial secret.
#
# hardirq: crypto.shash and crypto.skcipher refuse a hardirq runtime in its body and past it. A sha256 and a ctr(aes)
# the script shares through lunatik._ENV digest and encrypt the vectors in the body, which runs with IRQs on before
# the runtime is armed, and their methods refuse a callback they are handed over to, since it runs with IRQs disabled.
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
# irqsoff: shash and skcipher methods refuse a softirq runtime's hid raw_event reached with IRQs off, as an HCD
# without HCD_BH reaches it, through a HID transport the test builds whose one report comes from hardirq context.
#
# seed: rng and reset without a seed seed an algorithm with seedsize() random bytes, ansi_cprng's 48.
#
# sig: crypto.sig verifies the kernel's own ECDSA P-256 vector and an RSA PKCS#1 v1.5 pair openssl
# signed, each verifier allocated by its 6.13 name and, on ENOENT, by the name of 6.12 and earlier.
#
# kpp: crypto.kpp agrees ECDH secrets the kernel's P-256, P-384 and, where it serves the curve, P-192
# vectors give and two generated keys agree on, opens a secret an ephemeral key wrapped for a key
# generated in the kernel through hkdf and gcm(aes), answers nil and EINVAL for a peer's key the curve
# refuses on P-256 and P-384, which only the binding's check answers, a driver's own refusal raising, and
# refuses a private key a byte short of each vector's, of another length, out of range, or for another
# key agreement. crypto.kpp is nil where the kernel has no ECDH, and the
# script then raises as for an algorithm the kernel does not serve; where the kernel serves
# ecdh-nist-p256, which /proc/crypto lists once crypto-ecdh loads, that raise is a binding that was not
# built, and the case fails.
#
# kpp_status: kpp raises EIO for an engine's positive status, from a module the test builds that answers
# atmel-ecc's "ECC Fault" for one key's set_secret, and for another's public key and, from a worker,
# its shared secret.
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

# the options of the classes test $1 reaches
needs() {
	case $1 in
	shash|hkdf) echo CONFIG_CRYPTO_HASH2 ;;
	skcipher) echo CONFIG_CRYPTO_SKCIPHER2 ;;
	aead) echo CONFIG_CRYPTO_AEAD2 ;;
	rng) echo CONFIG_CRYPTO_RNG2 ;;
	sig) echo CONFIG_CRYPTO_SIG2 CONFIG_CRYPTO_HASH2 ;;
	kpp) echo CONFIG_CRYPTO_AEAD2 CONFIG_CRYPTO_HASH2 ;;
	quic|hardirq) echo CONFIG_CRYPTO_HASH2 CONFIG_CRYPTO_SKCIPHER2 ;;
	comp) echo CONFIG_CRYPTO_ACOMP2 ;;
	esac
}

for t in $TESTS; do
	if option=$(lacking $(needs "$t")); then
		ktap_skip "crypto/$t: needs $option"
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
bash "$DIR/irqsoff.sh" || RESULT=1
echo ""
bash "$DIR/seed.sh" || RESULT=1
echo ""
bash "$DIR/refused.sh" || RESULT=1
echo ""
bash "$DIR/kpp_status.sh" || RESULT=1
exit $RESULT

