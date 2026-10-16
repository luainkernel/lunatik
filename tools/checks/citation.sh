#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A rule cited is a rule read: a reply that says what AGENTS.md, a rule or a skill asks carries the
# passage in double quotes, and the passage is in the tree. "O AGENTS pede PR própria para um defeito
# que não depende do resto" recommended splitting #1896 by a rule AGENTS.md did not have. Takes text
# files, a reply among them; prints each line that cites a rule with no passage, or with one no
# Markdown file the tree tracks holds, and exits 1.
#
# Usage: bash tools/checks/citation.sh <file>...

root=$(cd "$(dirname "$0")/../.." && pwd)
cites='(\b(o|a|do|da|pelo|pela|the)|^) ?(AGENTS(\.md)?|CLAUDE\.md|regra|rule|skill|[a-z-]+\.md)\b[^.;:]{0,60}\b(pede|pedem|diz|dizem|manda|exige|pro[ií]be|requer|obriga|prev[eê]|p[oõ]e|determina|asks|says|requires|forbids|demands)\b'

# what the tree says, one line, its backticks and emphasis gone and its spacing squeezed
flat() {
	tr '\n' ' ' | sed -E 's/[`*]//g; s/[[:space:]]+/ /g' | tr '[:upper:]' '[:lower:]'
}
corpus=$(cd "$root" && git ls-files -z -- "*.md" | xargs -0 -r cat | flat)

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	n=0
	while IFS= read -r line; do
		n=$((n + 1))
		# a phrase quoted is one talked about, not one said
		said=$(printf '%s\n' "$line" | sed -E 's/"[^"]*"//g; s/“[^”]*”//g; s/`[^`]*`//g')
		printf '%s\n' "$said" | grep -qiE "$cites" || continue
		quotes=$(printf '%s\n' "$line" | grep -oE '"[^"]{20,}"|“[^”]{20,}”' | sed -E 's/^["“]//; s/["”]$//')
		if [ -z "$quotes" ]; then
			echo "$file:$n: cites a rule without its passage; quote the sentence, in double quotes, as the file has it: $line"
			status=1
			continue
		fi
		while IFS= read -r quote; do
			q=$(printf '%s' "$quote" | flat)
			case "$corpus" in
				*"$q"*) ;;
				*) echo "$file:$n: quotes \"$quote\", which no Markdown file of the tree holds; read the rule before citing it"
				   status=1 ;;
			esac
		done <<< "$quotes"
	done < "$file"
done
exit $status

