#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.kpp's sharedsecret refuses a peer's key the curve refuses before the transform sees it, so
# no driver computes with one, hisi_hpre and atmel-ecc included, which hand the point to their
# hardware unchecked. The suite counts on no such engine, so the case runs on the generic driver,
# which refuses the key itself once it computes, and is held to what only the binding's check
# produces: the refused key never enters the driver's computation.
#
# kpp_peer.lua, on ecdh-nist-p256-generic and ecdh-nist-p384-generic, answers nil and EINVAL for
# (1, 1), off both curves, for the point at infinity and for coordinates of all 0xff bytes, past
# each curve's prime, then agrees one secret a curve. A kprobe on crypto_ecdh_shared_secret, which
# the generic driver alone calls, and only to agree a secret, counts the calls made from the CLI's
# task, the one the script's body runs in, so another process agreeing a secret meanwhile is not
# counted: they are the two secrets agreed. A build that hands each key to the transform makes one
# for each refused key too. Skips where no kprobe can be placed on crypto_ecdh_shared_secret, and
# where the kernel serves either generic driver not at all, which the script allocates before its
# case and names.
#
# Usage: sudo bash tests/crypto/kpp_peer.sh

SCRIPT=tests/crypto/kpp_peer
ENTERED=lunatik_kpp_peer/agree
AGREED=2 # the secrets kpp_peer.lua agrees, one a curve

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	kprobe_remove "$ENTERED"
}
trap cleanup EXIT
cleanup

# the calls the CLI made, each trace line led by its task
entered() { awk -v event="${ENTERED#*/}:" '$1 ~ /^lunatik-/ && $5 == event' "$TRACING/instances/${ENTERED%%/*}/trace" | wc -l; }

# the script passes, and the driver agreed the secrets it agreed and nothing else
refused() {
	run_test "$SCRIPT" || return 1
	local calls
	calls=$(entered)
	[ "$calls" -eq "$AGREED" ] && return 0
	comment "crypto_ecdh_shared_secret ran $calls times for the $AGREED secrets agreed"
	return 1
}

ktap_header
ktap_plan 1

modprobe ecc 2> /dev/null # crypto_ecdh_shared_secret's module, which luacrypto loads only once the script runs
if ! kprobe_place "$ENTERED" crypto_ecdh_shared_secret; then
	ktap_skip "crypto/kpp_peer: couldn't place a kprobe on crypto_ecdh_shared_secret"
	ktap_totals
	exit 0
fi

served_case "crypto/kpp_peer" refused
ktap_totals

