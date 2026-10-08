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
# For each file given that defines a Lua module, a binding, a library under lib/,
# the core or a linux.* table autogen builds, prints the examples that require it
# or reach it through what tools/checks/modules.sh names, a library or a binding
# that hands its objects to a callback, so the reviewer and the Build phase know
# what to run. A deleted module is named from the base, which lists the examples
# the change left on it. Exits 1 when there is something to run.
#
# Usage: bash tools/checks/examples-touched.sh <file>...

source "$(dirname "$0")/modules.sh"

status=0

runnable() { # the directory of a multi-file example, the script of a single-file one
	local f=${1%.lua}
	case "$f" in examples/*/*) dirname "$f" ;; *) echo "$f" ;; esac
}

# the examples a README starts with the CLI verb whose runner function a change to the runner touches,
# both when it names neither: the CLI calls lunatik.runner.run or .spawn for them, and none of their
# scripts requires it (#1341)
started() {
	local verbs
	verbs=$(git diff -U0 "$CHECK_BASE" -- "$1" 2>/dev/null | grep -oE 'runner\.(run|spawn)\b' | sed 's/^runner\.//' | sort -u | paste -sd'|')
	grep -lE "lunatik (${verbs:-run|spawn})( |$)" examples/*/README.md 2>/dev/null | xargs -r -n 1 dirname
}

for file in "$@"; do
	# a change to an example's own files is a change to that example
	case "$file" in
		examples/*/*|examples/*.lua)
			echo "$file: run the example it changes, through tools/watchdog.sh: $(runnable "$file")"
			status=1
			continue
			;;
	esac
	mods=$(reaching_modules "$file")
	[ -n "$mods" ] || continue
	required=$(printf '%s\n' $mods | sed 's/\./\\./g' | paste -sd'|')
	examples=$({
		grep -rlE "require\(\"($required)(\.[a-z0-9_.]+)?\"\)" examples/ 2>/dev/null | while IFS= read -r f; do runnable "$f"; done
		[ "$file" = lib/lunatik/runner.lua ] && started "$file"
	} | sort -u | tr '\n' ' ')
	[ -n "$examples" ] || continue
	echo "$file: run the examples that use $(echo $mods | sed 's/ /, /g'), through tools/watchdog.sh: ${examples% }"
	status=1
done

exit $status

