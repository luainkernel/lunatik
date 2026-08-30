#!/bin/bash
# Runs cppcheck on a userspace test C file (tests/**/*.c). These are the
# standalone helpers (e.g. tests/netlink/channel_subscriber.c) that parse
# netlink wire data; cppcheck catches the resource-leak / uninitialized /
# some-bounds classes that -Wall/-Wextra and green tests miss. It is a net,
# not a substitute for reading every path.
# Scoped to tests/*.c only: cppcheck runs cleanly on userspace C. Kernel-module
# lib/*.c would need kernel include paths and produce noise, so it is excluded.
# Usage: cppcheck-tests.sh <file>...
# Prints the findings; exits 1 when there are any. Files outside its scope
# are skipped silently, so callers can pass any path.

command -v cppcheck > /dev/null 2>&1 || exit 0
rc=0

check() {
	local file="$1" findings

	case "$file" in
		*/tests/*.c|tests/*.c) ;;
		*) return 0 ;;
	esac
	[ -f "$file" ] || return 0

	# --library=posix so socket()/open()/etc. are tracked as resources (the
	# fd-leak case); warning+style for leaks, uninitialized vars, redundant code.
	findings=$(cppcheck --enable=warning,style --library=posix --quiet "$file" 2>&1 \
		| grep -E ':[0-9]+:[0-9]+:' | head -20)

	[ -z "$findings" ] && return 0
	printf 'cppcheck flagged %s — read each path before trusting it (bounds, termination, resource cleanup):\n%s\n' \
		"$(basename "$file")" "$findings"
	return 1
}

for f in "$@"; do
	check "$f" || rc=1
done
exit $rc

