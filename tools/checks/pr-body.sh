#!/usr/bin/env bash
# Checks a pull request body against AGENTS.md, "Patches and commits": at most three
# paragraphs, the first one the failure or the need, no em dash, no "Test plan" section,
# no failure named as a flake (untraced.sh), and a body tied to an issue in words GitHub
# does not act on (Part of, Top of, Bottom of, Answers, reported as) closes one or names
# the one it leaves open (closing.sh). Takes the body file; prints what fails and exits 1,
# silent otherwise. The footer an assistant appends (a line opening with an emoji) does not
# count.

. "$(dirname "$0")/closing.sh"

status=0
for file in "$@"; do
	body=$(grep -v '^🤖' "$file")
	paragraphs=$(printf '%s\n' "$body" | awk 'BEGIN{n=0; blank=1} /^[[:space:]]*$/{blank=1; next} {if (blank) n++; blank=0} END{print n}')
	if [ "$paragraphs" -gt 3 ]; then
		echo "$file: $paragraphs paragraphs; a body is the failure, the change and what it depends on, three at most"
		status=1
	fi
	if printf '%s' "$body" | grep -q '—'; then
		echo "$file: carries an em dash"
		status=1
	fi
	if printf '%s' "$body" | grep -qi 'test plan'; then
		echo "$file: carries a Test plan section"
		status=1
	fi
	if printf '%s\n' "$body" | grep -Eq "$(ties)" && ! printf '%s\n' "$body" | grep -Eiq "$(closes)|$(leaves)"; then
		echo "$file: tied to an issue, closes none: Closes #N, or #N, which it does not close"
		status=1
	fi
	bash "$(dirname "$0")/untraced.sh" "$file" || status=1
done
exit $status

