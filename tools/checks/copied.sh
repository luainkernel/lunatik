#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a function a change adds or edits in a C file of the tree that spells a run of tokens a
# function of code another project wrote spells, the Lua of lua/ and luac/ or klibc: that code is
# reused, not copied (AGENTS.md, *Deciding what to change*). #2347 copied the loop of project() in
# lua/lmathlib.c into lib/lualinux.c, 22 tokens in a row, under no note. A run is RUN tokens or more,
# comments and literals left out, made of K-token sequences both functions spell and no other C file
# of the tree does: a sequence the tree spells elsewhere is its own idiom, a call of the Lua API or of
# the kernel's, not a copy. A function under a note `based on <function>() @ <path>` follows that
# method on purpose and is not named for it.
#
# Heuristic: it annotates. Reads the functions whose lines the diff against CHECK_BASE (default HEAD)
# adds, every function of a file the repository does not track; reads nothing where the submodules
# are not checked out. Files outside its scope are skipped silently, so callers can pass any path.
#
# Usage: [CHECK_BASE=origin/master] bash tools/checks/copied.sh <file.c|file.h>...

status=0
base=${CHECK_BASE:-HEAD}
K=8
RUN=16

# the lines the change adds to a file, or "all" for one git does not track
added() {
	local dir name
	dir=$(dirname "$1"); name=$(basename "$1")
	git -C "$dir" ls-files --error-unmatch "$name" > /dev/null 2>&1 || { echo all; return; }
	git -C "$dir" diff -U0 "$base" -- "$name" 2> /dev/null |
		awk '/^@@/ { split($3, h, /[+,]/); n = (h[3] == "" ? 1 : h[3]); for (i = 0; i < n; i++) print h[2] + i }'
}

# each function of the files given, as "file<TAB>function<TAB>first line<TAB>last line<TAB>tokens"
functions() {
	awk '
	FNR == 1 { incomment = 0; depth = 0; name = ""; last = ""; called = ""; paren = 0; toks = "" }
	{
		s = $0
		if (incomment) { if (s !~ /\*\//) next; sub(/^([^*]|\*+[^*\/])*\*+\//, "", s); incomment = 0 }
		gsub(/\/\*([^*]|\*+[^*\/])*\*+\//, " ", s)
		if (s ~ /\/\*/) { sub(/\/\*.*$/, "", s); incomment = 1 }
		sub(/\/\/.*$/, "", s)
		if (match(s, /^[ \t]*#[ \t]*define[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) { called = substr(s, RSTART, RLENGTH); sub(/.*[ \t]/, "", called); paren = 0 }
		if (s ~ /^[ \t]*#/) next
		gsub(/"([^"\\]|\\.)*"/, " S ", s); gsub(/\047([^\047\\]|\\.)*\047/, " N ", s)
		while (s != "") {
			if (match(s, /^[ \t]+/)) { s = substr(s, RLENGTH + 1); continue }
			if (match(s, /^[A-Za-z_][A-Za-z0-9_]*/)) { t = substr(s, 1, RLENGTH); if (depth == 0) last = t }
			else if (match(s, /^(0[xX][0-9a-fA-F]+|[0-9]+)[uUlL]*/)) t = "N"
			else if (match(s, /^(>>=|<<=|->|\+\+|--|&&|\|\||==|!=|<=|>=|\+=|-=|\*=|\/=|%=|&=|\|=|\^=|<<|>>)/)) t = substr(s, 1, RLENGTH)
			else { RLENGTH = 1; t = substr(s, 1, 1) }
			s = substr(s, RLENGTH + 1)
			if (depth == 0 && t == "(" && paren++ == 0) called = last
			if (depth == 0 && t == ")") paren--
			if (depth == 0 && t == ";") called = ""
			if (t == "{" && depth++ == 0) { name = called; toks = ""; first = FNR }
			if (depth > 0) toks = toks " " t
			if (t == "}" && --depth == 0) {
				if (name != "") print FILENAME "\t" name "\t" first "\t" FNR "\t" toks
				name = ""; called = ""
			}
		}
	}' "$@"
}

copied() {
	local file="$1" lines top forks=() others=()
	lines=$(added "$file")
	[ -n "$lines" ] || return 1
	top=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2> /dev/null) || return 1
	mapfile -t forks < <(cd "$top" && ls lua/*.[ch] luac/*.c 2> /dev/null; find klibc/usr -name '*.c' 2> /dev/null)
	[ ${#forks[@]} -gt 0 ] || return 1
	while read -r other; do
		! [ "$top/$other" -ef "$file" ] && others+=("$top/$other")
	done < <(git -C "$top" ls-files '*.[ch]' ':!lua/' ':!luac/' ':!klibc/')

	{
		(cd "$top" && functions "${forks[@]}") | sed 's/^/F\t/'
		functions "${others[@]}" | sed 's/^/B\t/'
		functions "$file" | sed 's/^/T\t/'
	} | awk -F '\t' -v K=$K -v RUN=$RUN -v added="$lines" -v src="$file" '
	BEGIN {
		if (added == "all") every = 1
		else { m = split(added, a, "\n"); for (i = 1; i <= m; i++) mine[a[i]] = 1 }
		while ((getline line < src) > 0) text[++nl] = line
	}
	function touched(first, last,   i) {
		if (every) return 1
		for (i = first; i <= last; i++) if (i in mine) return 1
		return 0
	}
	# a note on one of the three lines above the body names the method the function follows
	function noted(first,   i) {
		for (i = first - 3; i < first; i++) if (i > 0 && match(text[i], /based on [A-Za-z_0-9]+\(\) @ [^ *]+/)) return substr(text[i], RSTART + 9, RLENGTH - 9)
		return ""
	}
	{
		n = split($6, t, " ")
		if ($1 == "T") { if (touched($4, $5)) { at[++nt] = $4; fn[nt] = $3; note[nt] = noted($4); size[nt] = n; for (i = 1; i <= n; i++) tok[nt, i] = t[i] } next }
		for (i = 1; i + K - 1 <= n; i++) {
			g = t[i]; for (j = i + 1; j < i + K; j++) g = g " " t[j]
			if ($1 == "F") { if (!(g in fork)) fork[g] = $3 "() @ " $2 }
			else back[g] = 1
		}
	}
	END {
		for (x = 1; x <= nt; x++) {
			delete cov; delete from
			for (i = 1; i + K - 1 <= size[x]; i++) {
				g = tok[x, i]; for (j = i + 1; j < i + K; j++) g = g " " tok[x, j]
				if ((g in fork) && !(g in back)) { from[fork[g]] = 1; for (j = i; j < i + K; j++) cov[fork[g], j] = 1 }
			}
			for (f in from) {
				run = 0; best = 0
				for (i = 1; i <= size[x]; i++) if ((f, i) in cov) { if (++run > best) best = run } else run = 0
				if (best < RUN || f == note[x]) continue
				printf "%s:%d: %s spells %d tokens in a row as %s does; code another project wrote is reused, not copied, and a method followed takes the note `based on %s` (AGENTS.md, *Deciding what to change*)\n", src, at[x], fn[x], best, f, f
				found = 1
			}
		}
		exit !found
	}'
}

for file in "$@"; do
	case "$file" in
		*/lua/*|lua/*|*/luac/*|luac/*|*/klibc/*|klibc/*|*/tests/*|tests/*|*.mod.c) continue ;;
		*.c|*.h) ;;
		*) continue ;;
	esac
	[ -f "$file" ] || continue
	copied "$file" && status=1
done

exit $status

