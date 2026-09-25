#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The shape rules of AGENTS.md, "Lua style", that a line-based read can find: an
# if/elseif whose branches repeat the same steps, which is a dispatch table or a
# helper; one table of arguments spelled at two call sites, which is declared
# once; and a function written inline as a table field, which is a named local
# function.
#
# Heuristic: it nudges at edit time and in review, it does not rewrite. Prints
# one finding per line and exits 1 when there are any; files outside its scope
# are skipped silently, so callers can pass any path.
#
# Usage: bash tools/checks/lua-style.sh <file>...

status=0

for file in "$@"; do
	case "$file" in
		*autogen/linux/*|*lib/linux/*|lua/*|*/lua/*|luac/*|*/luac/*) continue ;;
		*.lua) ;;
		*) continue ;;
	esac
	[ -f "$file" ] || continue

	awk -v file="$file" '
	function flag(n, why) { printf "%s:%d: %s\n", file, n, why; found = 1 }
	function indent(s) { match(s, /^\t*/); return RLENGTH }
	# the first step a statement takes: the call it makes or the name it assigns
	function head(s) {
		if (s ~ /^[[:space:]]*(if|elseif|else|end|for|while|repeat|until|return|local|break|goto|do)([^A-Za-z0-9_]|$)/) return ""
		if (match(s, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*([.:][A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*[({"]/)) {
			h = substr(s, RSTART, RLENGTH - 1); gsub(/[[:space:]]/, "", h); return h
		}
		if (match(s, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*=[^=]/)) {
			h = substr(s, RSTART, RLENGTH - 1); gsub(/[[:space:]]/, "", h); return h
		}
		return ""
	}
	# branches of the chain at depth d mirror each other when most of their steps coincide
	function compare(d,   i, j, k, n, common, shorter) {
		for (i = 1; i < nb[d]; i++) for (j = i + 1; j <= nb[d]; j++) {
			common = 0; n = (len[d, i] < len[d, j] ? len[d, i] : len[d, j])
			for (k = 1; k <= n; k++) if (step[d, i, k] == step[d, j, k]) common++
			if (common >= 3 && common >= n - 1) {
				flag(start[d], "if/elseif branches repeat the same " common " steps; a dispatch table or a helper (AGENTS.md, Lua style)")
				return
			}
		}
	}
	function branch(d) { nb[d]++; len[d, nb[d]] = 0 }
	function fields(t, n,   a, i, m, p) {	# the "key = value" pairs of a table constructor, its own level only
		sub(/^[^{]*\{/, "", t); sub(/\}[^}]*$/, "", t)
		while (gsub(/\{[^{}]*\}/, "", t)) ;
		m = split(t, a, /,/)
		for (i = 1; i <= m; i++) {
			p = a[i]; gsub(/^[[:space:]{]+|[[:space:]}]+$/, "", p); gsub(/[[:space:]]+/, " ", p)
			if (p ~ /^[A-Za-z_][A-Za-z0-9_]* ?= ?[^=]/) { sub(/ ?= ?/, "=", p); pairs[n, p] = 1; count[n]++ }
		}
	}
	{
		line = $0
		gsub(/"([^"\\]|\\.)*"/, "\"\"", line); gsub(/\047([^\047\\]|\\.)*\047/, "\"\"", line)
		sub(/--.*$/, "", line)
		d = indent(line)

		# a function written as the value of a table field
		if (line ~ /[{,][[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*function[[:space:]]*\(/)
			flag(NR, "a function inline in a table field; a named local function referenced by name (AGENTS.md, Lua style)")

		# the argument table of a call, collected to its closing brace
		if (!intable && match(line, /[A-Za-z0-9_\])][[:space:]]*\(?[[:space:]]*\{/)) {
			intable = 1; tstart = NR; text = substr(line, RSTART + RLENGTH - 1); depthb = 0
		}
		else if (intable) text = text "," line
		if (intable) {
			t = (tstart == NR ? text : line)
			depthb += gsub(/\{/, "{", t) - gsub(/\}/, "}", t)
			if (depthb <= 0) {
				nt++; tline[nt] = tstart; fields(text, nt)
				for (o = 1; o < nt; o++) {
					shared = 0
					for (key in pairs) { split(key, kp, SUBSEP); if (kp[1] == nt && ((o, kp[2]) in pairs)) shared++ }
					if (shared >= 3) {
						flag(tstart, "the call on line " tline[o] " spells " shared " of these fields too; declare the table once")
						break
					}
				}
				intable = 0
			}
		}

		# an if/elseif chain, its branches and the steps each one takes
		if (line ~ /^[[:space:]]*if[[:space:]].*[[:space:]]then[[:space:]]*$/) { open[d] = 1; nb[d] = 0; start[d] = NR; branch(d); next }
		if (open[d] && line ~ /^[[:space:]]*(elseif[[:space:]].*[[:space:]]then|else)[[:space:]]*$/) { branch(d); next }
		if (open[d] && line ~ /^[[:space:]]*end[[:space:]]*[),]?[[:space:]]*$/) { compare(d); open[d] = 0; next }
		if (d > 0 && open[d - 1]) {
			h = head(line)
			if (h != "") { b = nb[d - 1]; len[d - 1, b]++; step[d - 1, b, len[d - 1, b]] = h }
		}
	}
	END { exit !found }
	' "$file" && status=1
done

exit $status

