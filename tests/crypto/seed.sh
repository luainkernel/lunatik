#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.rng() and rng:reset() without a seed seed the algorithm with seedsize() random bytes the
# kernel draws, as crypto_get_default_rng() seeds the kernel's own generator, so an algorithm that
# refuses an empty seed can be created and reseeded. The stimulus is ansi_cprng, whose seed is 48
# bytes, V, key and DT, and which refuses one under 32 with EINVAL: it is created, reports a seed
# size of 48 and gives other bytes than a second one created beside it, each seed drawn; two
# generators reset with one seed give the same bytes, and other bytes once each is reset again
# without a seed; a seed of 31 bytes and an empty one are refused with EINVAL, a given seed
# reaching the algorithm as it is. Skips where the kernel has no ansi_cprng, and unloads it when
# the test loaded it.
#
# Usage: sudo bash tests/crypto/seed.sh

SCRIPT=tests/crypto/seed

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

CPRNG_LOADED=0
cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	[ "$CPRNG_LOADED" = 1 ] && modprobe -r ansi_cprng 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if ! modinfo ansi_cprng > /dev/null 2>&1; then
	ktap_skip "crypto/seed: ansi_cprng unavailable"
	ktap_totals
	exit 0
fi
lsmod | grep -q '^ansi_cprng ' || CPRNG_LOADED=1

if run_test "$SCRIPT"; then
	ktap_pass "crypto/seed"
else
	ktap_fail "crypto/seed"
fi
ktap_totals

