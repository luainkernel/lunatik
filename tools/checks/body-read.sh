#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Whether a reader with none of a change's history passed a pull request body: the lunatik-reader
# agent records the text it restated from the body alone and found nothing in it that a reviewer
# cannot follow, by the text's hash, under the guards' directory, and pr-body-guard.sh refuses the
# session's post of a body none recorded. The checks read the form of a body, and #2527's passed
# them all and reached the maintainer unreadable. A text changed after the read is one nobody read.
# Usage: body-read.sh <body file>          exits 0 when a reader passed this text, 1 otherwise
#        body-read.sh --pass <body file>   records the pass

pass=
[ "$1" = --pass ] && { pass=1; shift; }
[ -f "$1" ] || { echo "body-read: no body file at $1" >&2; exit 2; }

dir=${LUNATIK_GUARD_DIR:-/tmp/lunatik-guards}/read
# the text, whatever newlines end the file: a body gh api reads out of JSON ends in one
key=$(printf '%s\n' "$(cat "$1")" | sha256sum | cut -d ' ' -f 1)
if [ -n "$pass" ]; then
	mkdir -p "$dir" && : > "$dir/$key"
	exit
fi
[ -f "$dir/$key" ]

