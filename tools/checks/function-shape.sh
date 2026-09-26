#!/usr/bin/env bash
# Names the shapes of a C function a review round on #1158 passed over and the maintainer
# then called out: a lock taken at more than one site of one function, where the section
# between is a helper of its own; one buffer freed at more than one site of one function, the
# end and each raise path, where a userdata the collector frees is the shape; a function past
# forty lines or nested past two blocks, which is more than one job;
# and a per-item buffer sized by a maximum, n * LUARCU_MAXKEY, which is packed by each
# item's length. Takes file paths and reads the functions the diff against CHECK_BASE
# (default HEAD) touches, every function of a file the repository does not track; CHECK_ALL=1
# reads every function. Annotates, does not fail: a lock retaken after a wait is a shape the
# reader decides on, and the line names where to look.
#
# Usage: [CHECK_BASE=origin/master] bash tools/checks/function-shape.sh <file.c>...

base=${CHECK_BASE:-HEAD}

for file in "$@"; do
	case "$file" in */lua/*|lua/*|*/klibc/*|klibc/*) continue ;; *.c|*.h) ;; *) continue ;; esac
	[ -f "$file" ] || continue
	changed=""
	if [ -z "${CHECK_ALL:-}" ] && git -C "$(dirname "$file")" ls-files --error-unmatch "$(basename "$file")" >/dev/null 2>&1; then
		changed=$(git -C "$(dirname "$file")" diff -U0 "$base" -- "$(basename "$file")" 2>/dev/null |
			awk '/^@@/ { split($3, p, ","); from = substr(p[1], 2); n = (p[2] == "" ? 1 : p[2]); if (n > 0) print from, n }')
		[ -n "$changed" ] || continue
	fi
	awk -v f="$file" -v changed="$changed" '
	BEGIN {
		n = split(changed, ranges, "\n")
		for (i = 1; i <= n; i++) { split(ranges[i], p, " "); from[i] = p[1]; to[i] = p[1] + p[2] - 1 }
		LINES = 40; DEPTH = 3; SITES = 2
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
	}
	!infn && /^[A-Za-z_].*\(/ && !/;[ \t]*$/ && !/^#/ && !/^\/\*/ { hdr = NR; hname = $0; sub(/\(.*/, "", hname); sub(/.*[ \t*]/, "", hname) }
	!infn && /^\{[ \t]*$/ && hdr && NR - hdr <= 4 {
		infn = 1; start = hdr; name = hname; lines = 0; depth = 0; maxdepth = 0; slot = ""
		delete sites; delete frees
		next
	}
	infn {
		if ($0 ~ /^\}/) { report(); infn = 0; hdr = 0; next }
		lines++
		line = $0; gsub(/\/\*[^*]*\*\//, "", line)
		opens = gsub(/\{/, "{", line); closes = gsub(/\}/, "}", line)
		depth += opens; if (depth > maxdepth) maxdepth = depth; depth -= closes
		if (match(line, /(rcu_read_lock|lunatik_lock|spin_lock[a-z_]*|mutex_lock|read_lock|write_lock)\(/))
			sites[substr(line, RSTART, RLENGTH - 1)]++
		if (match(line, /(kfree|kvfree|lunatik_free|kfree_rcu|kvfree_rcu)\([^,)]+/)) { buf = substr(line, RSTART, RLENGTH); sub(/.*\(/, "", buf); frees[buf]++ }
		if (match(line, /\*[ \t]*[A-Za-z_]*(MAX|BUFFERSIZE)[A-Za-z_]*/) && slot == "") { slot = substr(line, RSTART + 1, RLENGTH - 1); sub(/^[ \t]+/, "", slot) }
	}
	' "$file"
done
exit 0

