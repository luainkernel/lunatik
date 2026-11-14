#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Checks a pull request body against AGENTS.md, "Patches and commits": at most four
# paragraphs outside its fenced examples, the first one the failure or the need in one plain sentence, no em dash, no "Test plan" section,
# no failure named as a flake (untraced.sh), and a body tied to an issue in words GitHub
# does not act on (Part of, Top of, Bottom of, Answers, reported as) closes one or names
# the one it leaves open (closing.sh), and no footer an assistant appends, which a
# Co-Authored-By trailer on the commit replaces. With the files the change carries, as
# examples-named.sh takes them, a change that reaches what a script writes or calls shows it
# in a fenced block or says why no script is shown, and the commits' own words, the cases'
# plumbing, the fixups and the push, stay out of a body whose change is not the tests or the
# harness; with none, it asks for no example and looks for those words in every body. Takes the body
# file and the changed files; prints what fails and exits 1, silent otherwise.
# Usage: pr-body.sh <body file> [<changed file>...]

. "$(dirname "$0")/closing.sh"

[ $# -gt 0 ] || { echo "usage: pr-body.sh <body file> [<changed file>...]" >&2; exit 2; }

file=$1
shift
# a body the check cannot read passes nothing, as it would pass an empty one
body=$(cat "$file" 2> /dev/null) || { echo "$file: cannot be read"; exit 1; }

status=0
# an example in a fenced block counts as no paragraph
paragraphs=$(printf '%s\n' "$body" | awk 'BEGIN{n=0; blank=1} /^[[:space:]]*(```|~~~)/{fence=!fence; blank=1; next}
	fence{next} /^[[:space:]]*$/{blank=1; next} {if (blank) n++; blank=0} END{print n}')
if [ "$paragraphs" -gt 4 ]; then
	echo "$file: $paragraphs paragraphs; a body is the need, what the change lets a script do, what changes and what it costs, four at most"
	status=1
fi
# the first sentence's words outside its code spans: 81 is the longest a merged body opened on
words=$(printf '%s\n' "$body" | awk '/^[[:space:]]*(```|~~~)/{if (text != "") exit; fence=!fence; next}
	fence{next} /^[[:space:]]*$/{if (text != "") exit; next} {text = text " " $0}
	END{gsub(/`[^`]*`/, "`", text); if (match(text, /[.!?][[:space:]]+[A-Z#`"*(]/)) text = substr(text, 1, RSTART)
		n = split(text, word, /[[:space:]]+/); for (i = 1; i <= n; i++) count += word[i] ~ /[[:alnum:]]/; print count + 0}')
if [ "$words" -gt 81 ]; then
	echo "$file: the first sentence runs $words words; it is the failure or the need in one plain sentence, what a script meets, and the mechanism goes in the commits"
	status=1
fi
if printf '%s\n' "$@" | grep -qE '^(lib|common|bin/luaebpf/lib)/' &&
	! printf '%s\n' "$body" | grep -qE '^[[:space:]]*(```|~~~)' && ! printf '%s\n' "$body" | grep -qE '\b([Nn]othing a|[Nn]o) script\b'; then
	echo "$file: the change reaches what a script writes or calls, and the body shows no code: show it in a fenced block that reads on its own, or say why no script is shown, as \"Nothing a script calls changes\""
	status=1
fi
# the tests and the harness are where these words name the subject
if [ $# -eq 0 ] || [ -n "$(printf '%s\n' "$@" | bash "$(dirname "$0")/harness-mixed.sh" --outside | grep -v '^tests/')" ]; then
	backstage=$(printf '%s\n' "$body" | awk '/^[[:space:]]*(```|~~~)/{fence=!fence; next} !fence' | sed 's/`[^`]*`//g' |
		grep -oiE '\b(cells?|stimul(us|i)|plan lines?|fixups?|(auto)?squash(ed|es|ing)?|this push)\b' | sort -fu | paste -sd , | sed 's/,/, /g')
	if [ -n "$backstage" ]; then
		echo "$file: carries the commits' words ($backstage); a body says what a reader of the change meets, and how it was tested, fixed and pushed goes in the commits$([ $# -gt 0 ] || echo ", unless the change is the tests' or the harness's, which the changed files, given after the body, say")"
		status=1
	fi
fi
if printf '%s' "$body" | grep -q '—'; then
	echo "$file: carries an em dash"
	status=1
fi
if printf '%s' "$body" | grep -qi 'test plan'; then
	echo "$file: carries a Test plan section"
	status=1
fi
if printf '%s\n' "$body" | grep -Eq '^🤖|Generated with \[Claude Code\]'; then
	echo "$file: carries an assistant footer; the commit's Co-Authored-By trailer is the only one"
	status=1
fi
if printf '%s\n' "$body" | grep -Eq "$(ties)" && ! printf '%s\n' "$body" | grep -Eiq "$(closes)|$(leaves)"; then
	echo "$file: tied to an issue, closes none: Closes #N, or #N, which it does not close"
	status=1
fi
bash "$(dirname "$0")/untraced.sh" "$file" || status=1
bash "$(dirname "$0")/decision.sh" "$file" || status=1
exit $status

