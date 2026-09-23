#!/usr/bin/env bash
# SessionStart hook: the checkout a session starts in is where that session and every agent it
# launches read AGENTS.md, the skills and the guards, so one left behind master works to rules
# master has changed. Takes the checkout, default the current directory, and prints one line when
# its HEAD is behind refs/remotes/origin/master: how far, and the fast-forward that brings it level,
# which is run only on a checkout with no commit of its own and nothing tracked changed. Silent
# otherwise. It fetches nothing: the remote-tracking ref is shared by every worktree, and any
# session's fetch moves it.

top=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
upstream=refs/remotes/origin/master
git -C "$top" rev-parse -q --verify "$upstream^{commit}" >/dev/null || exit 0

count() {
	[ "$1" -eq 1 ] && echo "1 $2" || echo "$1 $3"
}

behind=$(git -C "$top" rev-list --count "HEAD..$upstream" 2>/dev/null)
[ "${behind:-0}" -gt 0 ] || exit 0

own=$(git -C "$top" rev-list --count "$upstream..HEAD")
# a status that refreshes the index takes the lock another session's git in this checkout needs
changed=$(GIT_OPTIONAL_LOCKS=0 git -C "$top" status --porcelain --untracked-files=no | wc -l)
held=""
[ "$own" -gt 0 ] && held="$(count "$own" commit commits) of its own"
[ "$changed" -gt 0 ] && held="${held:+$held and }$(count "$changed" "tracked file" "tracked files") changed"

level="git -C $top merge --ff-only origin/master"
if [ -z "$held" ]; then
	echo "checkout-behind: $top is $(count "$behind" commit commits) behind origin/master; $level brings it level"
else
	echo "checkout-behind: $top is $(count "$behind" commit commits) behind origin/master and has $held; $level brings it level once it has neither"
fi

