#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.kpp raises EIO where the engine answers a positive status, as atmel-ecc answers its chip's
# error code, which is not an errno: the constructor raises instead of returning an object without a
# key, and sharedsecret raises instead of returning an output buffer the driver never wrote. No test
# host carries the chip, so kpp_status.c registers one for the test, an ecdh-nist-p256 named
# lunatik-kpp-status, below the generic driver's priority, built against the running kernel's build
# tree as deferred.sh builds its acomp and loaded for the script. Every key it serves through the
# generic driver, so the kernel's self-test passes, but two: for a scalar of 0x01 bytes its set_secret
# answers 0x05, atmel's "ECC Fault", as atmel_ecdh_set_secret does when the chip refuses a key
# generation, and for a scalar of 0x02 bytes its generate_public_key answers 0x05 and its
# compute_shared_secret answers -EINPROGRESS and a worker completes the request with 0x05 10 ms
# later, as atmel_ecdh_done does.
#
# kpp_status.lua asserts the constructor, publickey and sharedsecret raise EIO, the shared secret's
# with a peer's key the generic driver made, on the curve, so the binding's own check lets it
# through; run_test reads no Lua error, warning or oops in dmesg. Skips where the kernel builds no
# ECDH or has no build tree, and unloads the module once the script that pins it stopped.
#
# Usage: sudo bash tests/crypto/kpp_status.sh

SCRIPT=tests/crypto/kpp_status
MODULE=kpp_status
BUILD="/lib/modules/$(uname -r)/build"
DIR="$(dirname "$(readlink -f "$0")")"
TMP=""

source "$DIR/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	grep -q "^$MODULE " /proc/modules && rmmod "$MODULE"
	[ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

lacks CONFIG_CRYPTO_ECDH && { ktap_skip "crypto/kpp_status: needs CONFIG_CRYPTO_ECDH"; ktap_totals; exit 0; }
[ -f "$BUILD/Makefile" ] || { ktap_skip "crypto/kpp_status: no build tree at $BUILD"; ktap_totals; exit 0; }

modprobe -q crypto-ecdh # the generic driver kpp_status.c falls back to, and crypto_ecdh_decode_key's module
TMP=$(mktemp -d)
cp "$DIR/$MODULE.c" "$TMP/"
echo "obj-m := $MODULE.o" > "$TMP/Kbuild"
make -C "$BUILD" M="$TMP" modules > "$TMP/build.log" 2>&1 ||
	{ comment "$(tail -5 "$TMP/build.log")"; fail "crypto/kpp_status: $MODULE.c did not build"; }
insmod "$TMP/$MODULE.ko" || fail "crypto/kpp_status: $MODULE.ko did not load"

run_test "$SCRIPT" || fail "crypto/kpp_status"
ktap_pass "crypto/kpp_status"
ktap_totals

