#!/usr/bin/env bash
# PreToolUse (Bash) hook: an install, reload or run over a tree that drops a crash
# guard reproduces the crash the guard prevents, and on the shared host that is a
# forced reboot. This blocks (exit 2) make install, lunatik reload/run/spawn/test and
# a direct test run while any worktree of the project, against its HEAD, removes a
# line carrying a guard, unless the command carries the CRASH_AB_OK=1 marker, set by
# hand once the maintainer authorized the experiment and named the machine it may
# take down. Silent (exit 0) on everything else. The marker forces the ask; it cannot
# check that the answer was yes, only that it was set on purpose.
# Matches the raw hook input, which embeds the command verbatim.

input=$(cat)

case "$input" in
	*"make install"*|*"lunatik reload"*|*"lunatik run"*|*"lunatik spawn"*|*"lunatik test"*|*"bash tests/"*|*"/run.sh"*) ;;
	*) exit 0 ;;
esac

case "$input" in
	*CRASH_AB_OK=1*) exit 0 ;;
esac

guards='lunatik_argcheckclass|lunatik_argchecknull|lunatik_checkobject|lunatik_checkpobject|LUNATIK_PRIVATECHECKER'
guards="$guards|luaL_argcheck|luaL_argexpected|luaL_checktype|luaL_checkudata|lunatik_checkruntime"
guards="$guards|lunatik_checkpercpu|lunatik_checkcontext|lunatik_checkclass|lunatik_cannotsleep"

project=${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)}
[ -d "$project" ] || exit 0

removed=$(git -C "$project" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | while read -r tree; do
	[ -d "$tree" ] || continue
	git -C "$tree" diff HEAD -U0 -- '*.c' '*.h' 2>/dev/null | grep -E '^-[^-]' | grep -E "$guards" | sed "s|^|$tree: |"
done)
[ -z "$removed" ] && exit 0

echo "crash-guard: a worktree drops a crash guard; installing or running it reproduces the crash the guard prevents, which on the shared host is a forced reboot:" >&2
echo "$removed" >&2
echo "crash-guard: commit the change if it is not an experiment; for an experiment, get the maintainer's authorization and the machine it may take down, then re-run with CRASH_AB_OK=1 as a command prefix." >&2
exit 2

