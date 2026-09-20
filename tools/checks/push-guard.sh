#!/usr/bin/env bash
# PreToolUse (Bash) hook: a push publishes whatever HEAD is when it runs. A rebase, a
# merge, a cherry-pick, an am or a revert that stops on a conflict leaves HEAD on the
# base with the branch's commits still to apply, and a push chained after it in the same
# command publishes that base as the branch. This blocks (exit 2) a git push in a command
# that also runs one of those, and a git push from a tree with one in progress, the
# session's cwd or any directory the command changes into, the latter unless the command
# carries the PUSH_OK=1 marker, set once git status was read and the push is meant; silent
# (exit 0) on everything else. Reads the command field of the raw hook input, which embeds it verbatim;
# the description beside it is not a command.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*push*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

text=$(command_text "$input")
case "$text" in
	*"git push"*|*"git -C "*" push"*) ;;
	*) exit 0 ;;
esac

if printf '%s' "$text" | grep -Eq '(^|[;&|(])[[:space:]]*git[[:space:]]+(rebase|merge|cherry-pick|am|revert)([[:space:]]|$)'; then
	echo "push-guard: the command runs a rebase, merge, cherry-pick, am or revert and a push; one that stops on a conflict leaves HEAD on the base, and the push publishes that as the branch. Read git status, then push as a command of its own." >&2
	exit 2
fi

case "$text" in
	*PUSH_OK=1*) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
trees=$(printf '%s\n' "$cwd"; printf '%s' "$text" | grep -oE '(^|[;&|(])[[:space:]]*cd[[:space:]]+[^[:space:];&|)]+' | sed -E 's/^[;&|(]?[[:space:]]*cd[[:space:]]+//; s/^\\?["'"'"']//; s/\\?["'"'"']$//')
while read -r tree; do
	[ -n "$tree" ] || continue
	case "$tree" in /*) ;; *) tree="$cwd/$tree" ;; esac
	[ -d "$tree" ] || continue
	gitdir=$(git -C "$tree" rev-parse --absolute-git-dir 2>/dev/null) || continue
	for state in rebase-merge:rebase rebase-apply:rebase MERGE_HEAD:merge CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert; do
		[ -e "$gitdir/${state%:*}" ] || continue
		echo "push-guard: $tree has a ${state#*:} in progress; finish or abort it, read git status, then push." >&2
		exit 2
	done
done <<< "$trees"
exit 0

