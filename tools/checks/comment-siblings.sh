#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a comment a change adds to one definition of a block whose other definitions carry
# none: a run of #define lines, the members of a struct or a union, or a run of Lua
# `local NAME <const>` lines. Either each of them has a reason worth a line or none does, and
# the reason a block's members share belongs in the commit body. #1670 carried a line above
# lunatik_isatomic among the predicates of lunatik.h, none of which has one, and a line on the
# first member of a struct whose second had none, until the maintainer asked what was special
# about them. A comment counts when it trails the definition's line or stands alone on the line
# above it; a blank line or any other line ends the block, and LDoc blocks are left out.
#
# Heuristic: it nudges at edit time and in review, it does not rewrite. Reads the lines the
# diff against CHECK_BASE (default HEAD) adds, every line of a file the repository does not
# track; prints one finding per line and exits 1 when there are any. Files outside its scope
# are skipped silently, so callers can pass any path.
#
# Usage: [CHECK_BASE=origin/master] bash tools/checks/comment-siblings.sh <file>...

status=0
base=${CHECK_BASE:-HEAD}

# the lines the change adds to a file, or "all" for one git does not track
added() {
	local dir name
	dir=$(dirname "$1"); name=$(basename "$1")
	git -C "$dir" ls-files --error-unmatch "$name" > /dev/null 2>&1 || { echo all; return; }
	git -C "$dir" diff -U0 "$base" -- "$name" 2> /dev/null |
		awk '/^@@/ { split($3, h, /[+,]/); n = (h[3] == "" ? 1 : h[3]); for (i = 0; i < n; i++) print h[2] + i }'
}

for file in "$@"; do
	case "$file" in
		*.mod.c|*lunatik_sym.h|*autogen/linux/*|*lib/linux/*) continue ;;
		*.c|*.h) lang=c ;;
		*.lua) lang=lua ;;
		*) continue ;;
	esac
	[ -f "$file" ] || continue
	lines=$(added "$file")
	[ -n "$lines" ] || continue

	awk -v lang="$lang" -v file="$file" -v lines="$lines" '
	BEGIN { all = (lines == "all"); split(lines, a, "\n"); for (i in a) if (a[i] != "") isadded[a[i]] = 1 }
	function lone(s) {	# a comment alone on its line, LDoc left out
		if (lang == "c") return s ~ /^[[:space:]]*\/\*[^*].*\*\/[[:space:]]*$/
		return s ~ /^[[:space:]]*--[^-]/
	}
	function trailing(s) {
		if (lang == "c") return s ~ /[^[:space:]].*\/\*.*\*\/[[:space:]]*\\?[[:space:]]*$/ && s !~ /^[[:space:]]*\/\*/
		return s ~ /[^[:space:]-].*--/
	}
	function kind(s) {
		if (lang == "lua") return s ~ /^local [A-Z][A-Z0-9_]*[[:space:]]+<const>/ ? "const" : ""
		if (cont) return "cont"
		if (s ~ /^#define [A-Za-z_]/) return "define"
		if (body && s ~ /^\t[A-Za-z_][^;]*;/) return "member"
		return ""
	}
	function judge() {	# judge the block that just ended
		if (count > 1)
			for (i = 1; i <= count; i++) {
				if (!noted[i] || !(all || (noteline[i] in isadded))) continue
				others = 0
				for (j = 1; j <= count; j++) if (j != i && noted[j]) others = 1
				if (!others) {
					printf "%s:%d: a comment on one %s of a block whose other %d carry none: a reason for each, or for none, and the shared one in the commit body\n", file, noteline[i], blockkind, count - 1
					found = 1
				}
			}
		count = 0; blockkind = ""
	}
	{
		line = $0
		if (lang == "c") {
			if (line ~ /^(typedef )?(struct|union)[^;(]*\{[[:space:]]*$/) { judge(); pending = 0; body = 1; cont = 0; next }
			if (body && line ~ /^\}/) { judge(); pending = 0; body = 0; next }
		}
		k = kind(line)
		if (lang == "c") cont = line ~ /\\[[:space:]]*$/
		if (k == "cont") next
		if (k == "") {
			if (lone(line)) { pending = NR; next }
			pending = 0; judge(); next
		}
		if (k != blockkind) { judge(); blockkind = k }
		count++
		noted[count] = 0
		if (trailing(line)) { noted[count] = 1; noteline[count] = NR }
		else if (pending && pending == NR - 1) { noted[count] = 1; noteline[count] = pending }
		pending = 0
	}
	END { judge(); exit !found }
	' "$file" && status=1
done

exit $status

