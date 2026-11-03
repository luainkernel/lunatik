#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A call the conventions settle is made, not handed to the maintainer: a finding goes to an issue, and
# the reply says its number. "Decisão: o ponto cego do crash-guard.sh vira issue?" asked him twice
# what the review's filing stage does unasked, and "gravo o `Update:` do groomer na #2118?" asked him,
# a fourth time, to post what an implement-issue run returns, which he ordered posted always. Takes
# text files, a reply among them; prints each decision line that asks either, and exits 1.
#
# Usage: bash tools/checks/settled.sh <file>...

settled='(decis(a|ã)o|decision):.*\b(vira(r)?|abr(e|ir|o)|registr(a|ar|o)|file|open)\b( (uma|um|an?|the))? (issue|issues)\b'
# the Update a run returns is named in code, `Update:`, so this reads the line with its code
posted='(decis(a|ã)o|decision):.*\b(grav(a|ar|o)|post(a|ar|o)?|append|write)\b.*\b(update|label)\b'

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	# a phrase quoted, or code, is one talked about, not one said
	if asks=$(sed -E 's/`[^`]*`//g; s/"[^"]*"//g; s/[*_]//g' "$file" | grep -niE "$settled"); then
		printf '%s\n' "$asks" | sed "s|^|$file:|"
		echo "$file: asks whether to file a finding, which the conventions settle; file it and say its number"
		status=1
	fi
	if asks=$(sed -E 's/"[^"]*"//g; s/[*_`]//g' "$file" | grep -niE "$posted"); then
		printf '%s\n' "$asks" | sed "s|^|$file:|"
		echo "$file: asks whether to post a write an implement-issue run returned, which the maintainer ordered posted always; post it"
		status=1
	fi
done
exit $status

