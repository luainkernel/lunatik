#!/usr/bin/env bash
# Checks a pull request body against AGENTS.md, "Patches and commits": at most three
# paragraphs, the first one the failure or the need, no em dash and no "Test plan"
# section. Takes the body file; prints what fails and exits 1, silent otherwise. The
# footer an assistant appends (a line opening with an emoji) does not count.

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
done
exit $status

