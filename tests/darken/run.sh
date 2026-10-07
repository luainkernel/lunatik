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
# format darken.run reads. A script runs and hands back its values, as a chunk
# string.dump stripped of it does, darken.load hands one back loaded and not
# run, and an empty one, a ciphertext that is only its 16-byte tag, runs and
# returns none;
# a wrong key or IV, a flipped byte of the ciphertext or of the tag, and a
# ciphertext cut short, by one byte or below the tag, raise EBADMSG before
# anything loads; a ciphertext of 64 MiB, past kmalloc's largest block with 4K
# pages (KMALLOC_MAX_SIZE, 32 MiB at MAX_PAGE_ORDER 13), raises "not enough
# memory" and leaves no allocator WARN for the run's dmesg read, as a copy
# without __GFP_NOWARN does once per boot; an IV that is not 12 bytes and a key that is not 32 are
# refused; and a script that does not parse, a chunk that does not load and
# one that raises reach the caller with their own error.
#
# shade: tools/shade.sh, installed beside this script, encrypts a script and
# writes the key for its secret, and shade.lua runs the dark script through
# lighten with that key in place of light.lua, so the tag shade.sh derives
# from openssl's GMAC is the one gcm(aes) checks in the kernel. The script walks
# the stack and answers "shaded" only when neither darken.load nor darken.run is
# on it: the dark script calls what lighten.load returns as a tail call, so an
# encrypted module nests no deeper than a plain one. The same ciphertext run
# through lighten.run answers "nested", since darken.run calls the script from
# C, so the walk tells the two apart on every run. Skips below OpenSSL 3, whose
# openssl mac shade.sh needs.
#
# shade_chunk: the same script compiled by lunatic -s, the host compiler a
# product ships stripped chunks with, and then encrypted by tools/shade.sh, runs
# the same way. Skips without lunatic, and below OpenSSL 3.
#
# shade_error: a step of tools/shade.sh that fails, a secret that is not 64 hex
# digits and an option it does not take stop it with a non-zero status before
# it writes the dark script or light.lua. darken runs with an xxd ahead of the
# real one in PATH that fails where the encryption turns the ciphertext back
# into bytes for its GMAC, and darken and lighten with one that fails where the
# key's derivation turns its info string into hex; darken -s and lighten run
# with a secret of three hex digits and with one of 64 characters whose pairs
# each open with a hex digit, which hex2bin's printf takes; darken runs once
# more with an option it does not take, and lighten with -t after the secret,
# which getopts leaves as an operand, and with -s, which only darken takes.
# Skips below OpenSSL 3, where darken stops at its probe for openssl mac before
# any step.
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
RUN="$SCRIPTS/shade_run.lua"
TOOL="$DIR/shade.sh"
[ -e "$TOOL" ] || TOOL="$DIR/../../tools/shade.sh"
TMP=""

cleanup() {
	for s in "$SCRIPT" "$DECRYPT" "$SHADE"; do lunatik stop "$s" > /dev/null 2>&1; done
	rm -f "$DARK" "$LIGHT" "$RUN"
	[ -z "${TMP:-}" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup
TMP=$(mktemp -d)
cat > "$TMP/script.lua" <<'EOF'
local darken = require("darken")
local level = 2
while true do
	local info = debug.getinfo(level, "f")
	if info == nil then
		return "shaded"
	elseif info.func == darken.load or info.func == darken.run then
		return "nested"
	end
	level = level + 1
end
EOF

shade() {
	local name="${1:-script}" secret
	lunatik stop "$SHADE" > /dev/null 2>&1
	secret=$(bash "$TOOL" darken "$TMP/$name.lua") || return 1
	(cd "$TMP" && bash "$TOOL" lighten "$secret") || return 1
	sed 's/lighten\.load(\(.*\))(\.\.\.)$/lighten.run(\1)/' "$TMP/$name.dark.lua" > "$RUN" &&
		cp "$TMP/$name.dark.lua" "$DARK" && cp "$TMP/light.lua" "$LIGHT" && run_test "$SHADE"
}

shade_chunk() {
	lunatic -s -o "$TMP/chunk.lua" "$TMP/script.lua" && shade chunk
}

# shade.sh run in $TMP with these arguments exits non-zero and writes neither file
refuses() {
	rm -f "$TMP/script.dark.lua" "$TMP/light.lua"
	! (cd "$TMP" && bash "$TOOL" "$@" > /dev/null 2>&1) &&
		[ ! -e "$TMP/script.dark.lua" ] && [ ! -e "$TMP/light.lua" ]
}

shade_error() {
	local hex nothex
	hex=$(printf '%064d' 0)
	nothex=$(printf '0z%.0s' {1..32})
	mkdir -p "$TMP/bin"
	printf '#!/bin/sh\n[ "$1" = "$XXD_FAIL" ] && exit 1\nexec %s "$@"\n' "$(command -v xxd)" > "$TMP/bin/xxd"
	chmod +x "$TMP/bin/xxd"
	PATH="$TMP/bin:$PATH" XXD_FAIL=-r refuses darken script.lua &&
		PATH="$TMP/bin:$PATH" XXD_FAIL=-p refuses darken script.lua &&
		PATH="$TMP/bin:$PATH" XXD_FAIL=-p refuses lighten "$hex" &&
		refuses darken -s abc script.lua && refuses lighten abc &&
		refuses darken -s "$nothex" script.lua && refuses lighten "$nothex" &&
		refuses darken -x script.lua && refuses lighten "$hex" -t &&
		refuses lighten -s "$hex" "$hex"
}

ktap_header
ktap_plan 5

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

for name in shade shade_chunk shade_error; do
	if ! openssl mac -help > /dev/null 2>&1; then
		ktap_skip "darken/$name: tools/shade.sh needs OpenSSL 3 or later"
	elif [ "$name" = shade_chunk ] && ! command -v lunatic > /dev/null; then
		ktap_skip "darken/$name: lunatic not installed"
	elif $name; then
		ktap_pass "darken/$name"
	else
		ktap_fail "darken/$name"
	fi
done

ktap_totals

