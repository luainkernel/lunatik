#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A long reply opens with what the maintainer needs from it: past 15 lines, a TL;DR on one of its
# first two lines, five lines at most before the first blank line or heading after it. He asked
# "TL;DR" after a plan of 20 lines and after a report of 21. Takes text files, a reply among them;
# prints each one that runs long without it, or with a TL;DR that runs long itself, and exits 1.
#
# Usage: bash tools/checks/tldr.sh <file>...

LONG=15
SHORT=5

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	lines=$(grep -c '[^[:space:]]' "$file")
	[ "$lines" -gt "$LONG" ] || continue
	# the TL;DR's own lines, from its label to the first blank line or heading after it
	tldr=$(grep -v '^[[:space:]]*$' "$file" | head -n 2 | grep -qi 'tl;dr' && awk '
		!found && tolower($0) ~ /tl;dr/ { found = 1; if ($0 !~ /^#+[[:space:]]*\**tl;dr\**[[:space:]]*$/) n++; next }
		found && (/^[[:space:]]*$/ && n > 0 || /^#/) { exit }
		found && /[^[:space:]]/ { n++ }
		END { print n + 0 }' "$file")
	if [ -z "$tldr" ]; then
		echo "$file: runs $lines lines and opens with no TL;DR; open with one, five lines at most, that says what he needs from it"
		status=1
	elif [ "$tldr" -gt "$SHORT" ]; then
		echo "$file: its TL;DR runs $tldr lines; five at most, the detail below it"
		status=1
	fi
done
exit $status

