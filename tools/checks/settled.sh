#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A call the conventions settle is made, not handed to the maintainer: a finding goes to an issue, and
# the reply says its number. "Decisão: o ponto cego do crash-guard.sh vira issue?" asked him twice
# what the review's filing stage does unasked. Takes text files, a reply among them; prints each
# decision line that asks whether to file a finding, and exits 1.
#
# Usage: bash tools/checks/settled.sh <file>...

settled='(decis(a|ã)o|decision):.*\b(vira(r)?|abr(e|ir|o)|registr(a|ar|o)|file|open)\b( (uma|um|an?|the))? (issue|issues)\b'

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	# a phrase quoted, or code, is one talked about, not one said
	asks=$(sed -E 's/`[^`]*`//g; s/"[^"]*"//g; s/[*_]//g' "$file" | grep -niE "$settled") || continue
	printf '%s\n' "$asks" | sed "s|^|$file:|"
	echo "$file: asks whether to file a finding, which the conventions settle; file it and say its number"
	status=1
done
exit $status

