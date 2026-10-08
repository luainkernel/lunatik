#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a sequence of calls a change adds to a C file that another C file of the
# tree already spells: the sequence is one helper, in lunatik.h when its calls are
# the core's. #1584 wrote lua_pushnil, the
# errno's name and return 2 in luasocket_pushfail while #1595 wrote the same three
# lines in lualinux.c and luasignal.c, and the maintainer asked for lunatik_pushfail.
# A line is read for its shape, the calls it makes and what it returns, with the
# arguments and the name an assignment stores into left out, so the same steps
# over different values read as one sequence.
#
# Heuristic: it nudges at edit time and in review, it does not rewrite. Reads the
# lines the diff against CHECK_BASE (default HEAD) adds, every line of a file the
# repository does not track; prints one finding per line and exits 1 when there
# are any. Files outside its scope are skipped silently, so callers can pass any path.
#
# Usage: [CHECK_BASE=origin/master] bash tools/checks/core-helper.sh <file.c|file.h>...

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

repeated() {
	local file="$1" lines top others=()
	lines=$(added "$file")
	[ -n "$lines" ] || return 1
	top=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2> /dev/null) || return 1
	while read -r other; do
		! [ "$top/$other" -ef "$file" ] && others+=("$top/$other")
	done < <(git -C "$top" ls-files 'lib/*.[ch]' 'lunatik*.[ch]')
	# a file the change creates and has not staged is read beside the others it passes
	for other in "${targets[@]}"; do
		! [ "$other" -ef "$file" ] && ! git -C "$(dirname "$other")" ls-files --error-unmatch "$(basename "$other")" > /dev/null 2>&1 &&
			others+=("$other")
	done

	awk -v file="$file" -v added="$lines" -v top="$top/" '
	BEGIN {
		K = 3; Q = "\047"
		if (added == "all") every = 1
		else { m = split(added, a, "\n"); for (i = 1; i <= m; i++) mine[a[i]] = 1 }
	}
	function shape(s) {
		sub(/\\$/, "", s)
		gsub(/^[ \t]+|[ \t]+$/, "", s); gsub(/[ \t]+/, " ", s)
		while (gsub(/\([^()]*\)/, "\001", s)) ;
		gsub(/\001/, "()", s)
		sub(/^[A-Za-z_][A-Za-z0-9_ *]*[A-Za-z0-9_] ?= /, "_ = ", s)
		sub(/ ?\{$/, "", s)
		return s
	}
	function calls(s,   t, n, name) {
		t = s; n = 0
		while (match(t, /[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
			name = substr(t, RSTART, RLENGTH - 2)
			if (name !~ /^(if|for|while|switch|return|sizeof|unlikely|likely)$/) { n++; break }
			t = substr(t, RSTART + RLENGTH)
		}
		return n
	}
	FNR == 1 { n = 0; incomment = 0; depth = 0 }
	{
		s = $0
		if (incomment) { if (s !~ /\*\//) next; sub(/^.*\*\//, "", s); incomment = 0 }
		gsub(/\/\*([^*]|\*+[^*\/])*\*+\//, "", s)
		if (s ~ /\/\*/) { sub(/\/\*.*$/, "", s); incomment = 1 }
		gsub(/"([^"\\]|\\.)*"/, "\"\"", s); gsub(Q "([^" Q "\\\\]|\\\\.)" Q, Q Q, s)

		# a sequence lives in a function body: a line at file scope ends the one before it
		inbody = depth > 0
		depth += gsub(/\{/, "{", s) - gsub(/\}/, "}", s)
		if (!inbody) { n = 0; next }

		s = shape(s)
		if (s ~ /^(|\{|\}|\};|\} while \(\)|else|do|break;|default:|case .*:|\*.*|#.*)$/) next
		n++; txt[n] = s; at[n] = FNR; new[n] = (FILENAME == file && (every || (FNR in mine)))
		if (n < K) next

		# a window of K lines, two of them calls, not one call repeated, and long enough not to be boilerplate
		w = ""; size = 0; fresh = 1; c = 0; same = 1
		for (i = n - K + 1; i <= n; i++) {
			w = w (w == "" ? "" : " | ") txt[i]; size += length(txt[i]); c += calls(txt[i])
			if (!new[i]) fresh = 0
			if (txt[i] != txt[n]) same = 0
		}
		if (size < 30 || c < 2 || same) next

		where = FILENAME; sub("^" top, "", where); where = where ":" at[n - K + 1]
		# one finding for a run of overlapping windows that repeats the same place
		if (fresh && (w in seen)) {
			split(seen[w], p, ":")
			if (!((p[1], w) in told) && !(p[1] in last && at[n - K + 1] - last[p[1]] < K)) {
				printf "%s:%d: spells %s as %s does; a sequence two places spell is one helper, in lunatik.h when its calls are the core'"'"'s (.agents/rules/c.md)\n", file, at[n - K + 1], w, seen[w]
				told[p[1], w] = 1; found = 1
			}
			last[p[1]] = at[n - K + 1]
		}
		else if (FILENAME != file && !(w in seen)) seen[w] = where
	}
	END { exit !found }
	' "${others[@]}" "$file"
}

targets=("$@")
for file in "$@"; do
	case "$file" in
		*/lua/*|lua/*|*/luac/*|luac/*|*/klibc/*|klibc/*|*/tests/*|tests/*|*.mod.c) continue ;;
		*.c|*.h) ;;
		*) continue ;;
	esac
	[ -f "$file" ] || continue
	repeated "$file" && status=1
done

exit $status

