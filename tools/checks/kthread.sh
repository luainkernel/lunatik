#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The contract of AGENTS.md, "Kernel threads", that a line-based read can find: a
# loop that polls thread.shouldstop() gives the CPU up in its body, through
# linux.schedule(), a helper that calls it, or a call that blocks with a bound.
# The reader and writer bodies of tests/rcu/object_grace and map_sync looped on
# shouldstop() and a deadline with no pause of their own until #1167.
#
# Heuristic: it knows a pause by its name, schedule, yield, a receive, an accept,
# a wait or a sleep, in the loop or in a function of the same file the loop calls.
# Prints one finding per line and exits 1 when there are any; files outside its
# scope are skipped silently, so callers can pass any path.
#
# Usage: bash tools/checks/kthread.sh <file>...

status=0

for file in "$@"; do
	case "$file" in
		*autogen/linux/*|*lib/linux/*|lua/*|*/lua/*|luac/*|*/luac/*) continue ;;
		*.lua) ;;
		*) continue ;;
	esac
	[ -f "$file" ] || continue

	awk -v file="$file" '
	BEGIN { pause = "schedule[[:space:]]*\\(|yield[[:space:]]*\\(|receive|accept[[:space:]]*\\(|wait|sleep" }
	function indent(s) { match(s, /^\t*/); return RLENGTH }
	function report(n) {
		printf "%s:%d: a loop on thread.shouldstop() with no pause in its body; linux.schedule(), or a call bounded by a timeout (AGENTS.md, Kernel threads)\n", file, n
		found = 1
	}
	function calls(s,   name) {
		for (name in pausing)
			if (s ~ "(^|[^A-Za-z0-9_.:])" name "([^A-Za-z0-9_]|$)") return 1
		return 0
	}

	# the first read collects the functions whose bodies pause
	NR == FNR {
		line = $0; sub(/--.*$/, "", line)
		if (!fn && match(line, /^[[:space:]]*(local[[:space:]]+)?function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/)) {
			fn = line; sub(/^[[:space:]]*(local[[:space:]]+)?function[[:space:]]+/, "", fn); sub(/[[:space:]]*\(.*$/, "", fn)
			fdepth = indent(line); next
		}
		if (fn && indent(line) == fdepth && line ~ /^[[:space:]]*end([^A-Za-z0-9_]|$)/) fn = ""
		else if (fn && line ~ pause) pausing[fn] = 1
		next
	}
	{
		line = $0; sub(/--.*$/, "", line)

		# a while loop polls in its condition and closes on the end at its own depth
		if (!body && line ~ /^[[:space:]]*while[[:space:]].*shouldstop[[:space:]]*\(/) {
			body = "while"; start = FNR; depth = indent(line); paused = 0; next
		}
		# a repeat loop is known to poll only when its until is read
		if (!body && line ~ /^[[:space:]]*repeat[[:space:]]*$/) {
			body = "repeat"; start = FNR; depth = indent(line); paused = 0; next
		}
		if (!body) next

		if (indent(line) == depth && body == "while" && line ~ /^[[:space:]]*end([^A-Za-z0-9_]|$)/) {
			if (!paused) report(start)
			body = ""
		}
		else if (indent(line) == depth && body == "repeat" && line ~ /^[[:space:]]*until[[:space:]]/) {
			if (!paused && line ~ /shouldstop[[:space:]]*\(/) report(start)
			body = ""
		}
		else if (line ~ pause || calls(line))
			paused = 1
	}
	END { exit !found }
	' "$file" "$file" && status=1
done

exit $status

