#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a value the Lua of the compiler, bin/luaebpf, or of lib/ spells by hand beside a comment
# that names where the kernel defines it: a number beside a kernel symbol or a C source, as
# local SKB_LOAD_BYTES <const> = 26 -- BPF_FUNC_skb_load_bytes on #2235 and local MAXSTACK
# <const> = 512 -- MAX_BPF_STACK on #2202 were, of which the maintainer asked "why hardcoded?" and
# "shouldn't this come from autogen? why hardcoding this?"; and constants picked by name beside the
# C source that defines their set, as #2223 spelled the range of luakfunc_action in lib/luaxdp.c
# as action.ABORTED and action.REDIRECT. A comment counts when it trails the line, or stands above
# a run of top-level lines with no blank line between, which it then heads, named once.
#
# Heuristic: it nudges at edit time and in review, it does not rewrite. Reads the lines the
# diff against CHECK_BASE (default HEAD) adds, every line of a file the repository does not
# track; prints one finding per line and exits 1 when there are any. Files outside its scope
# are skipped silently, so callers can pass any path.
#
# Usage: [CHECK_BASE=origin/master] bash tools/checks/hardcoded.sh <file>...

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
	[ -f "$file" ] || continue
	# the path in the tree, so that a checkout under a directory named lib is not all in scope
	path=$(git -C "$(dirname "$file")" rev-parse --show-prefix 2> /dev/null)$(basename "$file")
	case "$path" in
		lib/linux/*) continue ;;
		bin/luaebpf/*.lua|lib/*.lua) ;;
		*) continue ;;
	esac

	awk -v file="$file" -v added="$(added "$file")" '
	BEGIN {
		if (added == "all") every = 1
		else { m = split(added, a, "\n"); for (i = 1; i <= m; i++) mine[a[i]] = 1 }
	}
	# where the comment opens, past the strings the line quotes, or 0
	function opens(s,   i, c, q) {
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (q != "") { if (c == "\\") i++; else if (c == q) q = ""; continue }
			if (c == "\"" || c == "\047") q = c
			else if (substr(s, i, 2) == "--") return i
		}
		return 0
	}
	# the kernel symbol a comment names, MAX_BPF_STACK or BPF_FUNC_skb_load_bytes, else its C source
	function cited(s,   name) {
		while (match(s, /[A-Z][A-Z0-9]*_[A-Za-z0-9_]*[A-Za-z0-9]/)) {
			name = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
			if (name !~ /^(OP|LUAI?L?)_/) return name	# the Lua the kernel links names its own, which autogen reads none of
		}
		return source(s)
	}
	function source(s) {
		if (match(s, /[A-Za-z0-9_\/.-]*[A-Za-z0-9_]\.[ch]([^A-Za-z0-9_]|$)/)) {
			s = substr(s, RSTART, RLENGTH); sub(/[^A-Za-z0-9_]$/, "", s); return s
		}
		return ""
	}
	function flag(n, what) {
		if (what ~ /\.[ch]$/) what = "what " what " defines"
		printf "%s:%d: spells %s by hand; a kernel constant is read from the linux.* table autogen/ generates, which autogen/specs.lua extends where it has none (.agents/rules/lua.md)\n", file, n, what
		found = 1
	}
	{
		at = opens($0)
		code = at ? substr($0, 1, at - 1) : $0
		note = at ? substr($0, at) : ""
		gsub(/"([^"\\]|\\.)*"|\047([^\047\\]|\\.)*\047/, "\"\"", code)
	}
	code ~ /^[[:space:]]*$/ && note == "" { heading = ""; inrun = 0; next }
	code ~ /^[[:space:]]*$/ { if (inrun) { heading = ""; inrun = 0 } heading = heading " " note; next }
	{
		if (!inrun) { inrun = 1; told = 0; top = ($0 ~ /^[A-Za-z_]/ && $0 !~ /^(local[[:space:]]+)?function[^A-Za-z0-9_]/) }
		if (!(every || (NR in mine))) next
		reads = code ~ /[A-Za-z_][A-Za-z0-9_]*\.[A-Z][A-Z0-9_]*([^A-Za-z0-9_]|$)/
		number = !reads && code ~ /(^|[^A-Za-z0-9_.])(0[xX][0-9A-Fa-f]+|[0-9]+)/
		picked = reads && code ~ /[^=<>~]=[^=]/
		if (number && (what = cited(note)) != "") flag(NR, what)
		else if (picked && (what = source(note)) != "") flag(NR, what)
		else if (top && !told && number && (what = cited(heading)) != "") { flag(NR, what); told = 1 }
		else if (top && !told && picked && (what = source(heading)) != "") { flag(NR, what); told = 1 }
	}
	END { exit !found }
	' "$file" && status=1
done

exit $status

