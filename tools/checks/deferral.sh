#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a deferral a change adds to the C of the core or of a binding: an item of the core's
# lunatik_defer, a work, an irq_work or a tasklet. AGENTS.md, "Deciding what to change", has a
# hazard refused in its context before it is engineered around, and a deferral that keeps an
# unsafe call working is weighed as a capability against that refusal. #1719 wrote the rule,
# and #1622 still carried a thread's stop handed to lunatik_defer, a back reference and a
# flush at its module's exit until the maintainer asked why the flush was needed; the end
# that could not wait was then left to the thread's own body, and the three went.
#
# Heuristic: a deferral can be the kernel's answer, as the core's deferred close is, so it
# annotates and the commit body names the refusal it was weighed against. Reads the lines the
# diff against CHECK_BASE (default HEAD) adds, every line of a file the repository does not
# track; prints one finding per line and exits 1 when there are any. Files outside its scope
# are skipped silently, so callers can pass any path.
#
# Usage: [CHECK_BASE=origin/master] bash tools/checks/deferral.sh <file>...

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
		*.mod.c|*lunatik_sym.h|*autogen/*|lua/*|*/lua/*|luac/*|*/luac/*|*klibc/*|tests/*|*/tests/*) continue ;;
		*.c|*.h) ;;
		*) continue ;;
	esac
	[ -f "$file" ] || continue
	lines=$(added "$file")
	[ -n "$lines" ] || continue

	awk -v file="$file" -v lines="$lines" '
	BEGIN {
		all = (lines == "all"); split(lines, a, "\n"); for (i in a) if (a[i] != "") isadded[a[i]] = 1
		deferral = "(^|[^A-Za-z0-9_])(lunatik_defer|lunatik_initdefer|queue_work|queue_delayed_work|schedule_work|schedule_delayed_work|irq_work_queue|init_irq_work|INIT_WORK|INIT_DELAYED_WORK|tasklet_schedule|tasklet_init|tasklet_setup)[[:space:]]*\\("
	}
	/^[[:space:]]*(\/?\*|#[[:space:]]*define)/ { next }
	(all || isadded[FNR]) && $0 ~ deferral {
		printf "%s:%d: a deferral this change adds: refuse the call in the context that makes it unsafe before deferring it, and name in the commit body the refusal it was weighed against (AGENTS.md, Deciding what to change)\n", file, FNR
		found = 1
	}
	END { exit found }
	' "$file" || status=1
done

exit $status

