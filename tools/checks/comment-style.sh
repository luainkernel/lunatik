#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The comment rules of AGENTS.md, "Comments and documentation", read over C, Lua
# and shell alike: a comment describes the present, not the history; it says why
# the code is what it is, not what would happen if something changed; inside code
# it is one line; and it does not push the line past the tree's width. The file
# header, LDoc blocks and doc-only comments are outside the rules; so are the
# unindented notes between Lua functions, and a shell script's narrative, which
# the Tests rules ask for.
#
# Heuristic: it nudges at edit time and in review, it does not rewrite. Prints
# one finding per line and exits 1 when there are any; files outside its scope
# are skipped silently, so callers can pass any path.
#
# Usage: bash tools/checks/comment-style.sh <file>...

status=0

for file in "$@"; do
	case "$file" in
		*.mod.c|*lunatik_sym.h|*autogen/linux/*|*lib/linux/*) continue ;;
		*.c|*.h) lang=c; width=110 ;;
		*.lua) lang=lua; width=120 ;;
		*.sh) lang=sh; width=120 ;;
		*) continue ;;
	esac
	[ -f "$file" ] || continue

	awk -v lang="$lang" -v width="$width" -v file="$file" '
	function flag(n, why) { printf "%s:%d: %s\n", file, n, why; found = 1 }
	function text(s) {
		# the comment on this line, lowercased, or "" when the line carries none
		if (lang == "c") {
			if (s ~ /\/\*\*\*/) return ""	# LDoc block
			if (match(s, /\/\*.*\*\//)) return tolower(substr(s, RSTART + 2, RLENGTH - 4))
			if (match(s, /\/\*.*$/)) return tolower(substr(s, RSTART + 2))
			if (match(s, /\/\/.*$/)) return tolower(substr(s, RSTART + 2))
			return ""
		}
		if (lang == "lua") {
			if (s ~ /^[[:space:]]*---/ || s ~ /^[[:space:]]*--[[:space:]]*@/) return ""	# LDoc
			if (match(s, /--.*$/)) return tolower(substr(s, RSTART + 2))
			return ""
		}
		if (s ~ /^#!/) return ""
		if (match(s, /(^|[[:space:]])#.*$/)) return tolower(substr(s, RSTART + 1))
		return ""
	}
	function whole(s) {	# the line is a comment and nothing else
		if (lang == "c") return s ~ /^[[:space:]]*(\/\*|\*|\/\/)/
		if (lang == "lua") return s ~ /^[[:space:]]*--/
		return s ~ /^[[:space:]]*#/
	}
	function incode() { return lang == "c" ? depth > 0 : seen_code }
	{
		line = $0
		t = text(line)

		# where we are: inside a function body (C: brace depth) or past the header (Lua, sh)
		if (lang == "c") {
			code = line; gsub(/"([^"\\]|\\.)*"/, "", code); gsub(/\/\*.*\*\//, "", code); sub(/\/\/.*$/, "", code)
			if (!inblock) { n = gsub(/\{/, "{", code); m = gsub(/\}/, "}", code) } else { n = 0; m = 0 }
		}
		if (t == "" && !whole(line) && line !~ /^[[:space:]]*$/) seen_code = 1

		if (t != "") {
			# the header before the first code line may tell the story a test guards against
			history = "(^|[^a-z])(no longer|used to|previously|formerly|any ?more|under the old)([^a-z]|$)"
			counterfactual = "(cannot|can.t|could not|couldn.t) [a-z ]*(afterwards|later)|would (have|otherwise)"
			if (incode() && t ~ history)
				flag(NR, "describes the history, not the present (AGENTS.md: no \"no longer\", \"used to\")")
			if (incode() && t ~ counterfactual)
				flag(NR, "says what would happen if something changed; say why the code is what it is")
			if (!whole(line) && length(line) > width)
				flag(NR, "trailing comment past " width " columns; one reason, shorter, or on its own line")
		}

		# a comment of more than one line inside code (the header and doc blocks are skipped)
		if (lang == "c") {
			if (!inblock && line ~ /\/\*/ && line !~ /\*\// && line !~ /\/\*\*\*/) { inblock = 1; start = NR; doc = 0 }
			else if (inblock && line ~ /\*\//) {
				if (depth > 0 && NR > start)
					flag(start, (NR - start + 1) " comment lines inside a function; one line carrying the reason")
				inblock = 0
			}
			if (!inblock) depth += n - m
		}
		else if (lang == "lua" && whole(line) && t != "" && line ~ /^[[:space:]]/) {	# indented, so inside a function
			if (run == 0) runstart = NR
			run++
		}
		else {
			if (run > 1 && incode()) flag(runstart, run " comment lines inside code; one line carrying the reason")
			run = 0
		}
	}
	END {
		if (run > 1 && incode()) flag(runstart, run " comment lines inside code; one line carrying the reason")
		exit !found
	}
	' "$file" && status=1
done

exit $status

