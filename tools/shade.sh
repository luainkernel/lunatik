#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# shade.sh — encrypt/decrypt tooling for Lunatik darken
#
# Usage:
#   shade.sh darken [-t] [-s secret] <script.lua>   encrypt a Lua script
#   shade.sh lighten [-t] <secret>                  generate light.lua from a secret
#
#   -t  use time-step salt for ephemeral key derivation (OTP)
#   -s  reuse an existing secret (darken only)
#
# darken needs OpenSSL 3 or later, for openssl mac.
# Both need bash 4.4 or later, for inherit_errexit.

set -euo pipefail
shopt -s inherit_errexit

die() { echo "error: $1" >&2; exit 1; }

hex2bin() { sed 's/../\\x&/g' | xargs -0 printf '%b'; }

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

# openssl enc refuses GCM: its ciphertext is CTR from IV || 2, its tag GMAC(ciphertext) ^ H * (len || len)
gcm_encrypt() {
	local key="$1" iv="$2" ct gmac h len fix
	ct=$(openssl enc -aes-256-ctr -K "$key" -iv "${iv}00000002" -nosalt -in "$3" | xxd -p | tr -d '\n')
	gmac=$(echo -n "$ct" | xxd -r -p | openssl mac -cipher AES-256-GCM -macopt "hexkey:${key}" \
		-macopt "hexiv:${iv}" GMAC)
	h=$(head -c 16 /dev/zero | openssl enc -aes-256-ecb -K "$key" -nopad | xxd -p)
	len=$(printf '%016x' $(( ${#ct} * 4 )))
	fix=$(gf128_mul "${len}${len}" "$h")
	printf '%s%016x%016x' "$ct" $(( 16#${gmac:0:16} ^ 16#${fix:0:16} )) $(( 16#${gmac:16:16} ^ 16#${fix:16:16} ))
}

hkdf_sha256() {
	local secret="$1" salt prk info
	salt="${2:-$(printf '%064x' 0)}"
	prk=$(echo -n "$secret" | hex2bin | openssl dgst -sha256 -mac HMAC \
		-macopt "hexkey:${salt}" -hex 2>/dev/null | sed 's/.*= //')

	info=$(printf 'lunatik-darken' | xxd -p | tr -d '\n')
	echo -n "${info}01" | hex2bin | openssl dgst -sha256 -mac HMAC \
		-macopt "hexkey:${prk}" -hex 2>/dev/null | sed 's/.*= //'
}

derive_key() {
	local secret="$1" salt
	[[ $secret =~ ^[[:xdigit:]]{64}$ ]] || die "secret must be 64 hex characters (32 bytes)"
	if $OTP; then
		salt=$(printf '%016x' "$(( $(date +%s) / 30 ))")
		hkdf_sha256 "$secret" "$salt"
	else
		hkdf_sha256 "$secret"
	fi
}

cmd_darken() {
	[ $# -eq 1 ] || die "usage: shade.sh darken [-t] [-s secret] <script.lua>"
	[ -f "$1" ] || die "file not found: $1"
	openssl mac -help > /dev/null 2>&1 || die "darken needs OpenSSL 3 or later, for openssl mac"

	local script="$1"
	local dark="${script%.lua}.dark.lua"
	local secret iv key ct

	secret="${SECRET:-$(openssl rand -hex 32)}"
	iv=$(openssl rand -hex 12)
	key=$(derive_key "$secret")

	ct=$(gcm_encrypt "$key" "$iv" "$script")

	cat > "$dark" <<-EOF
	local lighten = require("lighten")
	return lighten.run("${ct}", "${iv}")
	EOF

	echo "$secret"
}

cmd_lighten() {
	[ $# -ge 1 ] || die "usage: shade.sh lighten [-t] <secret>"

	local secret="$1" key

	key=$(derive_key "$secret")

	cat > light.lua <<-EOF
	return "${key}"
	EOF
}

[ $# -ge 1 ] || die "usage: shade.sh {darken|lighten} [-t] ..."

CMD="$1"; shift

OTP=false
SECRET=""
while getopts "ts:" opt; do
	case $opt in
		t) OTP=true ;;
		s) SECRET="$OPTARG" ;;
		*) exit 1 ;;
	esac
done
shift $((OPTIND - 1))

case "$CMD" in
	darken)  cmd_darken "$@" ;;
	lighten) cmd_lighten "$@" ;;
	*)       die "unknown command: $CMD" ;;
esac

