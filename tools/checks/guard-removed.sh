#!/usr/bin/env bash
# Names the crash guards a C file drops against HEAD, for an editor or assistant to
# see at edit time: removing one and running the test that covers it reproduces the
# crash the guard prevents. Takes file paths; silent on files that drop none.
# crash-guard.sh blocks the install or run that would follow. A guard that moved, into a
# helper or onto another index, is not one dropped: guards.sh pairs it with the line that took it.

. "$(dirname "$0")/guards.sh"

for file in "$@"; do
	case "$file" in *.c|*.h) ;; *) continue ;; esac
	removed=$(dropped_guards "$(dirname "$file")" "$(basename "$file")")
	[ -z "$removed" ] && continue
	echo "$file drops a crash guard against HEAD:"
	echo "$removed"
	echo "Running the test that covers it reproduces the crash the guard prevents; on the shared host that is a forced reboot. An experiment needs the maintainer's authorization and a machine that may go down (CRASH_AB_OK=1); otherwise commit, or restore the guard."
done

