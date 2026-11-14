#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Each constructor raises EINVAL for a name whose template refuses the type the constructor asks for,
# where the kernel hands the template's error to the allocation, 6.12 and later, and ENOENT where it
# does not, 6.11 and earlier: shash for cbc(aes), whose template builds a cipher, and skcipher, aead
# and sig for hmac(sha256), whose template builds a hash. sig answers ENOENT on 6.13 too, where the
# binding's crypto_has_alg check before the allocation answers every lookup that fails. This script
# writes a case's constructor, its name and the errno of the running release into refused_case.lua
# and runs the kernel script, once per case, and skips a case where the kernel's configuration has no
# option for its template, CONFIG_CRYPTO_CBC or CONFIG_CRYPTO_HMAC, without which 6.12 and later
# answer ENOENT too: an algorithm the kernel serves under the name is no proof of the template, since
# crypto/sha256.c registers hmac(sha256) itself from 6.17 and arm64's AES driver cbc(aes).
#
# Usage: sudo bash tests/crypto/refused.sh

SCRIPT=tests/crypto/refused
CASE=/lib/modules/lua/tests/crypto/refused_case.lua

# <constructor> <name> <the option of the name's template>
REFUSED="shash cbc(aes) CONFIG_CRYPTO_CBC
skcipher hmac(sha256) CONFIG_CRYPTO_HMAC
aead hmac(sha256) CONFIG_CRYPTO_HMAC
sig hmac(sha256) CONFIG_CRYPTO_HMAC"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	rm -f "$CASE"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

release=$(uname -r)
refused=EINVAL
printf '6.12\n%s\n' "$release" | sort -CV || refused=ENOENT

while read -r class name option; do
	if lacks "$option"; then
		ktap_skip "crypto/${class}_refused: needs $option"
		continue
	fi
	errno=$refused
	[ "$class" = sig ] && [[ "$release" == 6.13.* ]] && errno=ENOENT
	printf 'return {class = "%s", name = "%s", errno = "%s"}\n' "$class" "$name" "$errno" > "$CASE"
	served_case "crypto/${class}_refused" run_test "$SCRIPT"
	lunatik stop "$SCRIPT" > /dev/null 2>&1
done <<< "$REFUSED"
ktap_totals

