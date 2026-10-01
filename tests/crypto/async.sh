#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.skcipher() and crypto.aead() refuse an asynchronous implementation with
# ENOENT. Their requests carry no completion callback: a transform that answers
# -EINPROGRESS would have its output freed while it still writes there, and then
# complete through a NULL callback. On 6.12 and later the refusal is EEXIST,
# which the template answers when the lookup asks it again for the instance it
# already registered.
#
# cryptd is the asynchronous implementation any kernel can build: cryptd(<driver>)
# is <driver> behind cryptd's queue, flagged CRYPTO_ALG_ASYNC. The drivers are the
# null cipher and an authenc over it, whose instances take names no script asks
# for, so one left registered where cryptd stays loaded outranks nothing a script
# uses. The kernel registers the instance whether or not the lookup takes it, and
# /proc/crypto listing it as asynchronous is what shows the refusal answered an
# asynchronous implementation and not an unknown name. Skips when the kernel
# registered none, and unloads cryptd when the test loaded it.
#
# Usage: sudo bash tests/crypto/async.sh

SCRIPT=tests/crypto/async
DRIVERS="cryptd(ecb-cipher_null) cryptd(authenc(digest_null-generic,ecb-cipher_null))"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

CRYPTD_LOADED=0
cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	[ "$CRYPTD_LOADED" = 1 ] && modprobe -r cryptd 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

skip() { ktap_skip "$1"; ktap_totals; exit 0; }

isasync() {
	awk -v driver="$1" '$1 == "driver" {current = $3}
		$1 == "async" && current == driver && $3 == "yes" {found = 1}
		END {exit !found}' /proc/crypto
}

modinfo cryptd > /dev/null 2>&1 || skip "crypto/async: cryptd unavailable"
lsmod | grep -q '^cryptd ' || CRYPTD_LOADED=1

if ! run_test "$SCRIPT"; then
	ktap_fail "crypto/async"
	ktap_totals
	exit 1
fi

for driver in $DRIVERS; do
	isasync "$driver" || skip "crypto/async: the kernel registered no asynchronous $driver"
done
ktap_pass "crypto/async"
ktap_totals

