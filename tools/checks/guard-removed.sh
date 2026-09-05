#!/usr/bin/env bash
# Names the crash guards a C file drops against HEAD, for an editor or assistant to
# see at edit time: removing one and running the test that covers it reproduces the
# crash the guard prevents. Takes file paths; silent on files that drop none.
# crash-guard.sh blocks the install or run that would follow.

guards='lunatik_argcheckclass|lunatik_argchecknull|lunatik_checkobject|lunatik_checkpobject|LUNATIK_PRIVATECHECKER'
guards="$guards|luaL_argcheck|luaL_argexpected|luaL_checktype|luaL_checkudata|lunatik_checkruntime"
guards="$guards|lunatik_checkpercpu|lunatik_checkcontext|lunatik_checkclass|lunatik_cannotsleep"

for file in "$@"; do
	case "$file" in *.c|*.h) ;; *) continue ;; esac
	removed=$(git -C "$(dirname "$file")" diff HEAD -U0 -- "$(basename "$file")" 2>/dev/null | grep -E '^-[^-]' | grep -E "$guards")
	[ -z "$removed" ] && continue
	echo "$file drops a crash guard against HEAD:"
	echo "$removed"
	echo "Running the test that covers it reproduces the crash the guard prevents; on the shared host that is a forced reboot. An experiment needs the maintainer's authorization and a machine that may go down (CRASH_AB_OK=1); otherwise commit, or restore the guard."
done

