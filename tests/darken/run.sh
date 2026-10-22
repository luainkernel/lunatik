#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the darken tests and reports aggregated KTAP results.
#
# context, decrypt, shade and shade_chunk skip where the kernel serves no gcm(aes), the
# algorithm darken decrypts with, which each script allocates before its cases and names.
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
# writes the key for its secret, which lighten reads in upper case where darken
# prints it in lower, and shade.lua runs the dark script through
# lighten with that key in place of light.lua, so the tag shade.sh computes
# over openssl's AES is the one gcm(aes) checks in the kernel. The script walks
# the stack and answers "shaded" only when neither darken.load nor darken.run is
# on it: the dark script calls what lighten.load returns as a tail call, so an
# encrypted module nests no deeper than a plain one. The same ciphertext run
# through lighten.run answers "nested", since darken.run calls the script from
# C, so the walk tells the two apart on every run.
#
# shade_chunk: the same script compiled by lunatic -s, the host compiler a
# product ships stripped chunks with, and then encrypted by tools/shade.sh, runs
# the same way. Skips without lunatic.
#
# shade_error: a step of tools/shade.sh that fails, a secret that is not 64 hex
# digits, an option it does not take and a secret on the command line stop it
# with a non-zero status before it writes the dark script or light.lua. darken
# runs with an xxd ahead of the real one in PATH that fails where the
# encryption turns the ciphertext into hex, and with one that fails where it
# turns the counter blocks of the tag into bytes, and lighten with an openssl
# that fails where it derives the key; darken -s and lighten read a secret of
# three hex digits and one of 64 characters that are not all hex digits, which
# openssl would take as a password; darken runs once more with an option it
# does not take and with the secret after -s, and lighten with the secret as an
# operand and with -s, which only darken takes.
#
# shade_mode: tools/shade.sh lighten writes light.lua readable by its owner
# alone whatever the umask, 022 and then 002, and over a light.lua of mode 664
# it writes a new file, so a link to the old one, as a descriptor open on it
# would, keeps reading what it held and not the key. shade and shade_chunk run
# with such a key, which the kernel opens as the root task that loads the
# script.
#
# shade_argv: darken, lighten and darken -s, the last two with -t as well, run
# with a PATH that holds only a wrapper for each command tools/shade.sh runs,
# which logs its arguments, and neither the secret nor the key is among them,
# since a command line is what any local user reads in /proc. A command the
# PATH does not hold fails the case, so one tools/shade.sh comes to run is
# logged once it is added here.
#
# Each case that runs tools/shade.sh skips without openssl.
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
	(cd "$TMP" && bash "$TOOL" lighten <<< "${secret^^}") || return 1
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
	local hex nothex tool
	hex=$(printf '%064d' 0)
	nothex=$(printf '0z%.0s' {1..32})
	mkdir -p "$TMP/bin"
	for tool in xxd openssl; do
		printf '#!/bin/sh\n[ "$1" = "$FAIL" ] && exit 1\nexec %s "$@"\n' "$(command -v $tool)" > "$TMP/bin/$tool"
		chmod +x "$TMP/bin/$tool"
	done
	PATH="$TMP/bin:$PATH" FAIL=-p refuses darken script.lua &&
		PATH="$TMP/bin:$PATH" FAIL=-r refuses darken script.lua &&
		PATH="$TMP/bin:$PATH" FAIL=enc refuses lighten <<< "$hex" &&
		refuses darken -s script.lua <<< abc && refuses lighten <<< abc &&
		refuses darken -s script.lua <<< "$nothex" && refuses lighten <<< "$nothex" &&
		refuses darken -x script.lua && refuses darken -s "$hex" script.lua <<< "$hex" &&
		refuses lighten "$hex" <<< "$hex" && refuses lighten -s <<< "$hex"
}

# shade.sh lighten run in $TMP under the umask $1 writes light.lua of mode 600
lightens() {
	(cd "$TMP" && umask "$1" && bash "$TOOL" lighten <<< "$(printf '%064d' 0)") &&
		[ "$(stat -c %a "$TMP/light.lua")" = 600 ]
}

shade_mode() {
	rm -f "$TMP/light.lua" "$TMP/held.lua"
	lightens 022 && echo held > "$TMP/held.lua" && chmod 664 "$TMP/held.lua" &&
		ln -f "$TMP/held.lua" "$TMP/light.lua" && lightens 002 && [ "$(cat "$TMP/held.lua")" = held ]
}

# shade.sh run in $TMP with a PATH of wrappers that log the arguments of each command it runs
logged() {
	(cd "$TMP" && PATH="$TMP/argv" "$BASH" "$TOOL" "$@")
}

shade_argv() {
	local log="$TMP/argv.log" tool secret key stepkey
	mkdir -p "$TMP/argv"
	for tool in cat date install openssl sed tail tr wc xxd; do
		printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec %s "$@"\n' "$log" "$(command -v $tool)" > "$TMP/argv/$tool"
		chmod +x "$TMP/argv/$tool"
	done
	secret=$(logged darken script.lua) && logged lighten <<< "$secret" &&
		logged darken -s script.lua <<< "$secret" > /dev/null &&
		key=$(sed -n 's/^return "\(.*\)"$/\1/p' "$TMP/light.lua") &&
		logged darken -t -s script.lua <<< "$secret" > /dev/null && logged lighten -t <<< "$secret" &&
		stepkey=$(sed -n 's/^return "\(.*\)"$/\1/p' "$TMP/light.lua") && grep -q '^enc .* -S ' "$log" &&
		! grep -qiF -e "$secret" -e "$key" -e "$stepkey" "$log"
}

ktap_header
ktap_plan 7

if ! [ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] ||
	! grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"; then
	ktap_skip "darken/context: the loaded $MODULE does not carry the refusal: it would allocate under a spinlock"
else
	served_case "darken/context" run_test "$SCRIPT"
fi

served_case "darken/decrypt" run_test "$DECRYPT"

for name in shade shade_chunk shade_error shade_mode shade_argv; do
	if ! command -v openssl > /dev/null; then
		ktap_skip "darken/$name: openssl not installed"
	elif [ "$name" = shade_chunk ] && ! command -v lunatic > /dev/null; then
		ktap_skip "darken/$name: lunatic not installed"
	else
		served_case "darken/$name" "$name"
	fi
done

ktap_totals

