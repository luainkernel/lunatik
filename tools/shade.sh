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

set -euo pipefail

die() { echo "error: $1" >&2; exit 1; }

hex2bin() { sed 's/../\\x&/g' | xargs -0 printf '%b'; }

hkdf_sha256() {
	local secret="$1"
	local salt="${2:-$(printf '%064x' 0)}"
	local prk=$(echo -n "$secret" | hex2bin | openssl dgst -sha256 -mac HMAC \
		-macopt "hexkey:${salt}" -hex 2>/dev/null | sed 's/.*= //')

	local info=$(printf 'lunatik-darken' | xxd -p | tr -d '\n')
	echo -n "${info}01" | hex2bin | openssl dgst -sha256 -mac HMAC \
		-macopt "hexkey:${prk}" -hex 2>/dev/null | sed 's/.*= //'
}

derive_key() {
	local secret="$1"
	if $OTP; then
		local salt=$(printf '%016x' "$(( $(date +%s) / 30 ))")
		hkdf_sha256 "$secret" "$salt"
	else
		hkdf_sha256 "$secret"
	fi
}

cmd_darken() {
	[ $# -eq 1 ] || die "usage: shade.sh darken [-t] [-s secret] <script.lua>"
	[ -f "$1" ] || die "file not found: $1"

	local script="$1"
	local dark="${script%.lua}.dark.lua"

	local secret="${SECRET:-$(openssl rand -hex 32)}"
	local iv=$(openssl rand -hex 16)
	local key=$(derive_key "$secret")

	local ct=$(openssl enc -aes-256-ctr -K "$key" -iv "$iv" -nosalt \
		-in "$script" | xxd -p | tr -d '\n')

	cat > "$dark" <<-EOF
	local lighten = require("lighten")
	return lighten.run("${ct}", "${iv}")
	EOF

	echo "$secret"
}

cmd_lighten() {
	[ $# -ge 1 ] || die "usage: shade.sh lighten [-t] <secret>"

	local secret="$1"
	[ ${#secret} -eq 64 ] || die "secret must be 64 hex characters (32 bytes)"

	local key=$(derive_key "$secret")

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
	esac
done
shift $((OPTIND - 1))

case "$CMD" in
	darken)  cmd_darken "$@" ;;
	lighten) cmd_lighten "$@" ;;
	*)       die "unknown command: $CMD" ;;
esac

