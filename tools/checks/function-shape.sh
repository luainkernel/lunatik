#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names the shapes of a C function a review round on #1158 passed over and the maintainer
# then called out: a lock taken at more than one site of one function, where the section
# between is a helper of its own; one buffer freed at more than one site of one function, the
# end and each raise path, where a userdata the collector frees is the shape; a function past
# thirty lines or nested past two blocks, which is more than one job;
# a per-item buffer sized by a maximum, n * LUARCU_MAXKEY, which is packed by each
# item's length; a function that existed at CHECK_BASE and that the diff grows by five lines or
# more, whose new step is a helper of its own, as #1879's hook clear grew lunatik_pcallobject; and
# one condition tested at two sites of one function, the bracket of a guard, which is a pair of
# helpers that mirror. A Lua file is held to the same length and depth, and to four branches,
# counted by its if, elseif, for, while and repeat: the maintainer asked of call.CALL on #2202, grown
# by a fifth arm in 24 lines, "this function seems too complex/long and should be modularized; we
# are committing the same flaw over and over again". Each Lua function the change adds or grows past
# them is named, as #948 grew declare to 38 lines and ten branches. Takes file paths and reads the
# functions the diff against CHECK_BASE
# (default HEAD) touches, every function of a file the repository does not track; CHECK_ALL=1
# reads every function. Annotates, does not fail: a lock retaken after a wait is a shape the
# reader decides on, and the line names where to look.
#
# Usage: [CHECK_BASE=origin/master] bash tools/checks/function-shape.sh <file.c|file.lua>...

base=${CHECK_BASE:-HEAD}
# names of their own: bash sets LINES to the terminal's height after each command a terminal runs
MAXLINES=30 MAXDEPTH=3 MAXBRANCHES=4

# each top-level function of the Lua on stdin, a named function to the end at column 0, as
# "name start lines depth branches", read past strings, comments and long brackets
luafunctions() {
	awk '
	function own(s,   out, ends, i) {
		while (s != "") {
			if (inlong) {
				ends = "]" level "]"
				if (!(i = index(s, ends))) break
				s = substr(s, i + length(ends)); inlong = 0
			}
			else if (match(s, /(--)?\[=*\[/)) {
				out = out substr(s, 1, RSTART - 1); level = substr(s, RSTART, RLENGTH); sub(/^(--)?\[/, "", level); sub(/\[$/, "", level)
				inlong = 1; s = substr(s, RSTART + RLENGTH)
			}
			else return out s
		}
		return out
	}
	{
		code = own($0)
		gsub(/"([^"\\]|\\.)*"|\047([^\047\\]|\\.)*\047/, "\"\"", code); sub(/--.*$/, "", code)
	}
	!infn && (code ~ /^(local[ \t]+)?function[ \t]+[A-Za-z_][A-Za-z0-9_.:]*[ \t]*\(/ ||
	          code ~ /^[A-Za-z_][A-Za-z0-9_.]*[ \t]*=[ \t]*function[ \t]*\(/) {
		if (code ~ /[^A-Za-z0-9_]end[ \t]*$/) next
		name = code; sub(/^(local[ \t]+)?(function[ \t]+)?/, "", name); sub(/[ \t]*[=(].*$/, "", name)
		infn = 1; start = NR; lines = 0; depth = 0; deepest = 0; branches = 0
		next
	}
	infn && code ~ /^end([^A-Za-z0-9_]|$)/ { print name, start, lines, deepest, branches; infn = 0; next }
	infn {
		lines++
		gsub(/[^A-Za-z0-9_]/, " ", code); n = split(code, word, " ")
		for (i = 1; i <= n; i++) {
			if (word[i] ~ /^(if|do|function|repeat)$/) { if (++depth > deepest) deepest = depth }
			else if (word[i] ~ /^(end|until)$/) depth--
			if (word[i] ~ /^(if|elseif|for|while|repeat)$/) branches++
		}
	}'
}

for file in "$@"; do
	case "$file" in */lua/*|lua/*|*/klibc/*|klibc/*|*autogen/linux/*) continue ;; *.c|*.h|*.lua) ;; *) continue ;; esac
	[ -f "$file" ] || continue
	changed=""
	existed=""
	if [ -z "${CHECK_ALL:-}" ] && git -C "$(dirname "$file")" ls-files --error-unmatch "$(basename "$file")" >/dev/null 2>&1; then
		changed=$(git -C "$(dirname "$file")" diff -U0 "$base" -- "$(basename "$file")" 2>/dev/null |
			awk '/^@@/ { split($3, p, ","); from = substr(p[1], 2); n = (p[2] == "" ? 1 : p[2]); if (n > 0) print from, n }')
		[ -n "$changed" ] || continue
	fi
	if [[ $file == *.lua ]]; then
		# the functions the file had at the base, which a change grows rather than writes
		[ -z "$changed" ] || existed=$(git -C "$(dirname "$file")" show "$base:./$(basename "$file")" 2>/dev/null | luafunctions)
		luafunctions < "$file" | awk -v f="$file" -v changed="$changed" -v existed="$existed" -v all="${CHECK_ALL:-}" \
			-v LINES=$MAXLINES -v DEPTH=$MAXDEPTH -v BRANCHES=$MAXBRANCHES '
		BEGIN {
			m = split(existed, rows, "\n")
			for (i = 1; i <= m; i++) { split(rows[i], p, " "); had[p[1]] = 1; oldlines[p[1]] = p[3]; oldbranches[p[1]] = p[5] }
		}
		{
			name = $1; start = $2; lines = $3; deepest = $4; branches = $5
			# untracked, every function; tracked, one the change adds, or grows in length or in branches
			if (!all && changed != "" && (name in had) && lines <= oldlines[name] && branches <= oldbranches[name]) next
			if (lines > LINES)
				printf "%s:%d: %s runs %d lines: more than one job, each a function\n", f, start, name, lines
			if (deepest >= DEPTH)
				printf "%s:%d: %s nests %d blocks deep: a block is a helper\n", f, start, name, deepest
			if (branches > BRANCHES)
				printf "%s:%d: %s branches %d ways: each arm is a function, a dispatch a table of its handlers\n", f, start, name, branches
		}'
		continue
	fi
	if [ -n "$changed" ]; then
		# the functions the file had at the base and their length, which a change grows rather than writes
		existed=$(git -C "$(dirname "$file")" show "$base:./$(basename "$file")" 2>/dev/null | awk '
			!infn && /^[A-Za-z_].*\(/ && !/;[ \t]*$/ && !/^#/ && !/^\/\*/ { hdr = NR; h = $0; sub(/\(.*/, "", h); sub(/.*[ \t*]/, "", h) }
			!infn && /^\{[ \t]*$/ && hdr && NR - hdr <= 4 { infn = 1; len = 0; next }
			infn && /^\}/ { print h, len; infn = 0; hdr = 0; next }
			infn { len++ }')
	fi
	awk -v f="$file" -v changed="$changed" -v existed="$existed" -v LINES=$MAXLINES -v DEPTH=$MAXDEPTH '
	BEGIN {
		n = split(changed, ranges, "\n")
		for (i = 1; i <= n; i++) { split(ranges[i], p, " "); from[i] = p[1]; to[i] = p[1] + p[2] - 1 }
		m = split(existed, names, "\n"); for (i = 1; i <= m; i++) { split(names[i], p, " "); old[p[1]] = p[2] }
		SITES = 2; GROWS = 5
	}
	function touched(s, e,   i) {
		if (n == 0) return 1
		for (i = 1; i <= n; i++) if (from[i] <= e && to[i] >= s) return 1
		return 0
	}
	function report(   lock, msg) {
		if (!touched(start, NR)) return
		for (lock in sites) if (sites[lock] >= SITES)
			printf "%s:%d: %s takes %s at %d sites: the section between is a helper of its own\n", f, start, name, lock, sites[lock]
		for (buf in frees) if (frees[buf] >= SITES)
			printf "%s:%d: %s frees %s at %d sites, the end and each raise path: a buffer the collector frees is a userdata\n", f, start, name, buf, frees[buf]
		if (lines > LINES)
			printf "%s:%d: %s runs %d lines: more than one job, each a function\n", f, start, name, lines
		if (maxdepth >= DEPTH)
			printf "%s:%d: %s nests %d blocks deep: a block is a helper\n", f, start, name, maxdepth
		if (slot != "")
			printf "%s:%d: %s sizes a slot by a maximum (%s): a per-item buffer is packed by each item'"'"'s length\n", f, start, name, slot
		if ((name in old) && lines - old[name] >= GROWS)
			printf "%s:%d: %s grows by %d lines: the step they take is a helper of its own, a guard around a call a pair of helpers that mirror\n", f, start, name, lines - old[name]
		for (cond in conds) if (conds[cond] >= SITES)
			printf "%s:%d: %s tests (%s) at %d sites: the bracket it opens and closes is a pair of helpers that mirror\n", f, start, name, cond, conds[cond]
	}
	!infn && /^[A-Za-z_].*\(/ && !/;[ \t]*$/ && !/^#/ && !/^\/\*/ { hdr = NR; hname = $0; sub(/\(.*/, "", hname); sub(/.*[ \t*]/, "", hname) }
	!infn && /^\{[ \t]*$/ && hdr && NR - hdr <= 4 {
		infn = 1; start = hdr; name = hname; lines = 0; depth = 0; maxdepth = 0; slot = ""
		delete sites; delete frees; delete conds
		next
	}
	infn {
		if ($0 ~ /^\}/) { report(); infn = 0; hdr = 0; next }
		lines++
		if ($0 ~ /^[ \t]+if \(.*\)[ \t]*$/) { cond = $0; sub(/^[ \t]+if \(/, "", cond); sub(/\)[ \t]*$/, "", cond); conds[cond]++ }
		line = $0; gsub(/\/\*[^*]*\*\//, "", line)
		opens = gsub(/\{/, "{", line); closes = gsub(/\}/, "}", line)
		depth += opens; if (depth > maxdepth) maxdepth = depth; depth -= closes
		if (match(line, /(rcu_read_lock|lunatik_lock|spin_lock[a-z_]*|mutex_lock|read_lock|write_lock)\(/))
			sites[substr(line, RSTART, RLENGTH - 1)]++
		if (match(line, /(kfree|kvfree|kfree_sensitive|kvfree_sensitive|lunatik_free|kfree_rcu|kvfree_rcu)\([^,)]+/)) { buf = substr(line, RSTART, RLENGTH); sub(/.*\(/, "", buf); frees[buf]++ }
		if (match(line, /\*[ \t]*[A-Za-z_]*(MAX|BUFFERSIZE)[A-Za-z_]*/) && slot == "") { slot = substr(line, RSTART + 1, RLENGTH - 1); sub(/^[ \t]+/, "", slot) }
	}
	' "$file"
done
exit 0

