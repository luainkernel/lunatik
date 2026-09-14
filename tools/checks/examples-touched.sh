#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A change to a binding is proven on the examples that use it, run through
# tools/watchdog.sh, not only on the suite: the suite covers what a test author
# thought of, and an example is what a user does with the binding at the rate
# they do it. Reviews of #795 and #837 ran the probe suite and never systrack,
# which arms a kprobe on every syscall and counts into an rcu table from each
# hit; its first run on the merged code took the host down.
#
# For each file given that defines a Lua module (lib/lua<name>.c through
# LUNATIK_NEWLIB, or a Lua library under lib/), prints the examples that require
# that module, directly or through a script they run, so the reviewer and the
# Build phase know what to run. Exits 1 when there is something to run.
#
# Usage: bash tools/checks/examples-touched.sh <file>...

status=0

module() {
	case "$1" in
		lib/luacrypto_*.c) echo crypto ;;
		lib/lua*.c) sed -nE 's/^LUNATIK_NEWLIB\(([a-z0-9_]+),.*/\1/p' "$1" | head -1 ;;
		lib/*.lua) local m=${1#lib/}; m=${m%.lua}; echo "${m//\//.}" ;;
	esac
}

runnable() { # the directory of a multi-file example, the script of a single-file one
	local f=${1%.lua}
	case "$f" in examples/*/*) dirname "$f" ;; *) echo "$f" ;; esac
}

for file in "$@"; do
	[ -f "$file" ] || continue
	mod=$(module "$file")
	[ -n "$mod" ] || continue
	examples=$(grep -rlE "require\(\"$mod(\.[a-z0-9_.]+)?\"\)" examples/ 2>/dev/null | while IFS= read -r f; do runnable "$f"; done | sort -u | tr '\n' ' ')
	[ -n "$examples" ] || continue
	echo "$file: run the examples that use $mod, through tools/watchdog.sh: ${examples% }"
	status=1
done

exit $status

