#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Checks a release's notes against the rules v5.0's were written to and that no guard read: no em
# dash, nothing promised of the API or of a release to come, which the maintainer keeps out of the
# public notes, no failure named as a flake (untraced.sh) and no decision handed over without the
# three (decision.sh). Notes run as long as the release, so pr-body.sh's three paragraphs and its
# Closes line are not theirs. Takes the notes file; prints what fails and exits 1, silent otherwise.

future='API (freeze|is frozen|stays frozen)|freezes? (the|its) (public )?API|frozen (public )?API|next (major |minor )?release|(upcoming|future|later) release|will be (fixed|addressed|resolved)'

status=0
for file in "$@"; do
	if grep -q '—' "$file"; then
		echo "$file: carries an em dash"
		status=1
	fi
	hits=$(grep -niE "$future" "$file")
	if [ -n "$hits" ]; then
		printf '%s\n' "$hits" | sed "s|^|$file:|"
		echo "$file: promises what a release to come does; the notes say what this one does"
		status=1
	fi
	bash "$(dirname "$0")/untraced.sh" "$file" || status=1
	bash "$(dirname "$0")/decision.sh" "$file" || status=1
done
exit $status

