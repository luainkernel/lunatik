#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# shade.sh — encrypt/decrypt tooling for Lunatik darken
#
# Usage:
#   shade.sh darken [-t] [-s] <script.lua>   encrypt a Lua script
#   shade.sh lighten [-t]                    generate light.lua from a secret
#
#   -t  use time-step salt for ephemeral key derivation (OTP)
#   -s  reuse an existing secret (darken only)
#
# lighten and darken -s read the secret on stdin, since any local user reads a command line in /proc.
#
# Both need OpenSSL 1.1.1 or later, for openssl enc -pbkdf2, and bash 4.4 or later, for inherit_errexit.

set -euo pipefail
shopt -s inherit_errexit

die() { echo "error: $1" >&2; exit 1; }

xor128() { printf '%016x%016x' $(( 16#${1:0:16} ^ 16#${2:0:16} )) $(( 16#${1:16:16} ^ 16#${2:16:16} )); }

# x * y in GF(2^128) with GCM's bit order (NIST SP 800-38D, algorithm 1), on 32 hex digits each
gf128_mul() {
	local mask=$(( (1 << 63) - 1 )) r=$(( 0xe1 << 56 ))
	local vh=$((16#${2:0:16})) vl=$((16#${2:16:16})) zh=0 zl=0 x i lsb
	for x in $((16#${1:0:16})) $((16#${1:16:16})); do
		for ((i = 63; i >= 0; i--)); do
			if (( x >> i & 1 )); then
				zh=$((zh ^ vh)) zl=$((zl ^ vl))
			fi
			lsb=$((vl & 1))
			vl=$(( (vl >> 1 & mask) | (vh & 1) << 63 ))
			vh=$(( (vh >> 1 & mask) ^ lsb * r ))
		done
	done
	printf '%016x%016x' "$zh" "$zl"
}

# openssl takes a raw key only as an argument, so it derives the key from the secret it reads on a descriptor
keyed() { openssl enc -pbkdf2 -iter 1 -md sha256 -pass fd:3 "${SALT[@]}" "$@" 3<<< "$SECRET"; }

# openssl enc refuses GCM: its ciphertext is CTR from IV || 2, its tag GHASH_H(ciphertext) ^ E(IV || 1), H = E(0)
gcm_encrypt() {
	local iv="$1" zero ct he x i
	zero=$(printf '%032x' 0)
	# OpenSSL 1.1.1 writes "Salted__" and the salt ahead of what it encrypts under -t, which tail -c drops
	ct=$(keyed -aes-256-ctr -iv "${iv}00000002" -in "$2" | tail -c "$(wc -c < "$2")" | xxd -p | tr -d '\n')
	he=$(xxd -r -p <<< "${zero}${iv}00000001" | keyed -aes-256-ecb -nopad | tail -c 32 | xxd -p | tr -d '\n')
	x=$zero
	for ((i = 0; i < ${#ct}; i += 32)); do
		x=$(gf128_mul "$(xor128 "$x" "${ct:i:32}${zero}")" "${he:0:32}")
	done
	x=$(gf128_mul "$(xor128 "$x" "$(printf '%016x%016x' 0 $(( ${#ct} * 4 )))")" "${he:0:32}")
	printf '%s%s' "$ct" "$(xor128 "$x" "${he:32:32}")"
}

read_secret() {
	read -r SECRET || : # a last line without its newline fails read, and the check below judges it
	[[ $SECRET =~ ^[[:xdigit:]]{64}$ ]] || die "secret must be 64 hex characters (32 bytes)"
	SECRET=${SECRET,,} # keyed hashes the text, and openssl rand -hex prints the 32 bytes in lower case
}

cmd_darken() {
	[ $# -eq 1 ] || die "usage: shade.sh darken [-t] [-s] <script.lua>, with the secret of -s on stdin"
	[ -f "$1" ] || die "file not found: $1"

	local script="$1"
	local dark="${script%.lua}.dark.lua"
	local iv ct

	if $REUSE; then
		read_secret
	else
		SECRET=$(openssl rand -hex 32)
	fi
	iv=$(openssl rand -hex 12)

	ct=$(gcm_encrypt "$iv" "$script")

	cat > "$dark" <<-EOF
	local lighten = require("lighten")
	return lighten.load("${ct}", "${iv}")(...)
	EOF

	echo "$SECRET"
}

cmd_lighten() {
	[[ $# -eq 0 && $REUSE == false ]] || die "usage: shade.sh lighten [-t], with the secret on stdin"

	local key

	read_secret
	key=$(keyed -aes-256-ecb -P | sed -n 's/^key=//p')

	install -m 0600 /dev/stdin light.lua <<-EOF
	return "${key}"
	EOF
}

[ $# -ge 1 ] || die "usage: shade.sh {darken|lighten} [-t] ..."

CMD="$1"; shift

SALT=(-nosalt)
REUSE=false
while getopts "ts" opt; do
	case $opt in
		t) SALT=(-S "$(printf '%016x' "$(( $(date +%s) / 30 ))")") ;;
		s) REUSE=true ;;
		*) exit 1 ;;
	esac
done
shift $((OPTIND - 1))

case "$CMD" in
	darken)  cmd_darken "$@" ;;
	lighten) cmd_lighten "$@" ;;
	*)       die "unknown command: $CMD" ;;
esac

