#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A primitive in lunatik.h that every class inherits (the lock, the allocator,
# the context checks) is changed for the caller that needs it, in the arm that
# caller takes, and the commit body names what else moves. #891's first shape
# fixed a kprobe handler by moving every softirq hook from bottom halves off
# to interrupts off, and said so in a footnote of the pull request.
#
# For each core file given, the primitives the change touches are mapped to
# the classes whose opt flags select an arm in them and to the files that call
# them, so the author and the reviewer see the whole surface a one-line change
# reaches. Exits 1 when a primitive changed; what to say about it is the
# commit body's job.
#
# The base is HEAD, the pull request's base once its diff is staged; on a
# committed branch pass it:
#
#     CHECK_BASE=origin/master bash tools/checks/blast-radius.sh lunatik.h
#
# Usage: bash tools/checks/blast-radius.sh <file>...

base=${CHECK_BASE:-HEAD}
status=0

classes() { # the classes carrying a flag: "name (file)"
	grep -rlE '\.opt = ' lunatik_*.c lib/*.c 2>/dev/null | while IFS= read -r f; do
		awk -v flag="$1" -v file="$f" '
			/\.name *= / { name = "?"; if (match($0, /"[^"]+"/)) name = substr($0, RSTART + 1, RLENGTH - 2) }
			/\.opt = / && index($0, flag) { printf "%s (%s) ", name, file }
		' "$f"
	done
}

for file in "$@"; do
	case "$file" in lunatik.h|lunatik_*.c) ;; *) continue ;; esac
	[ -f "$file" ] || continue
	changed=$(git diff -U0 "$base" -- "$file" 2>/dev/null | grep -oE '^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)?' | sed -E 's/.*\+([0-9]+)(,([0-9]+))?/\1 \3/')
	[ -n "$changed" ] || continue
	names=$(awk -v changed="$changed" '
		BEGIN { n = split(changed, lines, "\n"); for (i = 1; i <= n; i++) { split(lines[i], p, " "); from[i] = p[1]; to[i] = p[1] + (p[2] == "" ? 1 : p[2]) - 1 } }
		function touched(s, e,   i) { for (i = 1; i <= n; i++) if (from[i] <= e && to[i] >= s) return 1; return 0 }
		/^#define lunatik_[a-z_]+\(/ { name = $2; sub(/\(.*/, "", name); start = NR; inmacro = 1 }
		inmacro && !/\\$/ { if (touched(start, NR)) print name; inmacro = 0 }
		/^static inline .*lunatik_[a-z_]+\(/ { name = $0; sub(/\(.*/, "", name); sub(/.* /, "", name); sub(/^\*/, "", name); start = NR; infn = 1 }
		infn && /^}/ { if (touched(start, NR)) print name; infn = 0 }
	' "$file" | sort -u)
	[ -n "$names" ] || continue
	for name in $names; do
		body=$(awk -v name="$name" '
			$0 ~ "^#define " name "\\(" { on = 1 } on { print } on && !/\\$/ { exit }
			$0 ~ "^static inline .*" name "\\(" { fn = 1 } fn { print } fn && /^}/ { exit }
		' "$file")
		flags=$(grep -oE 'lunatik_is(irq|softirq|hardirq|monitor|single|external|percpu)' <<< "$body" | sed 's/lunatik_is//' | sort -u | tr '\n' ' ')
		callers=$(git grep -lw "$name" -- 'lunatik*.[ch]' 'lib/*.[ch]' | grep -v "^$file$" | wc -l)
		echo "$file: $name changed; called from $callers other files${flags:+; its arms select on ${flags% }}"
		keys=$(for flag in $flags; do
			case $flag in irq) echo LUNATIK_OPT_SOFTIRQ LUNATIK_OPT_HARDIRQ ;; *) echo "LUNATIK_OPT_${flag^^}" ;; esac
		done | tr ' ' '\n' | sort -u)
		for k in $keys; do
			c=$(classes "$k")
			[ -n "$c" ] && echo "  $k: ${c% }"
		done
		status=1
	done
done

[ $status -eq 0 ] || echo "say in the commit body which of these change behaviour, and keep the change to the arm the fix needs"
exit $status

