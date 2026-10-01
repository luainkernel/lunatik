#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the darken tests and reports aggregated KTAP results.
#
# context: darken.run allocates its transform with crypto_alloc_aead, which
# allocates with GFP_KERNEL and may load a module, so a hook of an
# interrupt-context runtime that calls it would sleep under the runtime's
# spinlock. context.lua creates a runtime in each context whose body, which runs
# in process context, decrypts and runs a chunk, and resumes it past the body:
# a process runtime runs the chunk again, and a softirq and a hardirq runtime,
# armed as a hook finds them, each refuse with the message the case asserts. A
# build without the refusal allocates the transform under the spinlock, so the
# case skips unless the loaded luadarken is the installed one and that file
# carries the refusal, which is inline and has no symbol of its own.
#
# decrypt: decrypt.lua seals each script with crypto.aead's gcm(aes), the
# format darken.run reads. A script runs and hands back its values, and an
# empty one, a ciphertext that is only its 16-byte tag, runs and returns none;
# a wrong key or IV, a flipped byte of the ciphertext or of the tag, and a
# ciphertext cut short, by one byte or below the tag, raise EBADMSG before
# anything loads; an IV that is not 12 bytes and a key that is not 32 are
# refused; and a script that does not parse, a precompiled one and one that
# raises reach the caller with their own error.
#
# shade: tools/shade.sh, installed beside this script, encrypts a script and
# writes the key for its secret, and shade.lua runs the dark script through
# lighten with that key in place of light.lua, so the tag shade.sh derives
# from openssl's GMAC is the one gcm(aes) checks in the kernel. Skips below
# OpenSSL 3, whose openssl mac shade.sh needs.
#
# Usage: sudo bash tests/darken/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT="tests/darken/context"
DECRYPT="tests/darken/decrypt"
SHADE="tests/darken/shade"
MODULE="luadarken"
REFUSAL="not allowed once the runtime is armed"
SCRIPTS="/lib/modules/lua/tests/darken"
DARK="$SCRIPTS/shade_dark.lua"
LIGHT="$SCRIPTS/shade_light.lua"
TOOL="$DIR/shade.sh"
[ -e "$TOOL" ] || TOOL="$DIR/../../tools/shade.sh"
TMP=""

cleanup() {
	for s in "$SCRIPT" "$DECRYPT" "$SHADE"; do lunatik stop "$s" > /dev/null 2>&1; done
	rm -f "$DARK" "$LIGHT"
	[ -z "${TMP:-}" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup
TMP=$(mktemp -d)

shade() {
	local secret
	printf 'return "shaded"\n' > "$TMP/script.lua"
	secret=$(bash "$TOOL" darken "$TMP/script.lua") || return 1
	(cd "$TMP" && bash "$TOOL" lighten "$secret") || return 1
	cp "$TMP/script.dark.lua" "$DARK" && cp "$TMP/light.lua" "$LIGHT" && run_test "$SHADE"
}

ktap_header
ktap_plan 3

if ! [ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] ||
	! grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"; then
	ktap_skip "darken/context: the loaded $MODULE does not carry the refusal: it would allocate under a spinlock"
elif run_test "$SCRIPT"; then
	ktap_pass "darken/context"
else
	ktap_fail "darken/context"
fi

if run_test "$DECRYPT"; then
	ktap_pass "darken/decrypt"
else
	ktap_fail "darken/decrypt"
fi

if ! openssl mac -help > /dev/null 2>&1; then
	ktap_skip "darken/shade: tools/shade.sh needs OpenSSL 3 or later"
elif shade; then
	ktap_pass "darken/shade"
else
	ktap_fail "darken/shade"
fi

ktap_totals

