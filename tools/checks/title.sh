#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Checks a pull request title or a commit subject against AGENTS.md, "Patches and commits": its area,
# a colon and what changes for whoever uses it, in one plain clause of 60 characters at most, with
# none of the words that open a subordinate clause, where, whose, which, so, as and their kin; a
# relative "that" is part of a plain clause. The why goes in the body. A fixup!, amend! or squash!
# subject, a revert, the Reapply git writes for the revert of one, and a merge pass. Takes each title
# as an argument, or one a line on stdin; prints what fails and exits 1, silent otherwise.
# Usage: title.sh [<title>...]

[ $# -gt 0 ] || { mapfile -t titles; set -- "${titles[@]}"; }

status=0
for title; do
	case $title in
		""|"fixup! "*|"amend! "*|"squash! "*|"Revert \""*|"Reapply \""*|"Merge "*) continue ;;
	esac
	if ! printf '%s\n' "$title" | grep -qE '^[A-Za-z0-9_./-]+(, [A-Za-z0-9_./-]+)*: [^ ]'; then
		echo "\"$title\": names no area; a title is \"<area>: <what changes for whoever uses it>\""
		status=1
	fi
	if [ ${#title} -gt 60 ]; then
		echo "\"$title\": runs ${#title} characters; a title is one plain clause of 60 at most, and the why goes in the body"
		status=1
	fi
	# the words of the clause after the area, its code spans left out; socket.so and issue-since.sh are names
	words=$(printf '%s\n' "${title#*: }" | sed 's/`[^`]*`//g' | tr -s ' ' '\n' | sed 's/^(//; s/[,;:)]*$//' |
		grep -xE 'where|whose|which|so|as|since|because|unless|when|while|whereas|although|though|if' | paste -sd , | sed 's/,/, /g')
	if [ -n "$words" ]; then
		echo "\"$title\": opens a subordinate clause ($words); a title is one plain clause, and the why goes in the body"
		status=1
	fi
done
exit $status

