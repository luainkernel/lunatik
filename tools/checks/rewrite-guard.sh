#!/usr/bin/env bash
# PreToolUse (Bash) hook: a force-push rewrites history, and every branch started
# from the one being rewritten keeps the commits it drops. They surface later as a
# duplicate of a commit that no longer exists, in a pull request nobody edited.
# AGENTS.md covers a branch checked out elsewhere and the body a rewrite invalidates;
# this covers the branches based on it, which is what `git push --force` cannot see.
# Blocks (exit 2) a forced push of a branch other refs descend from. Reads the tool
# command on stdin. REWRITE_OK=1 runs it once the list below is known to be stale.

input=$(cat)

case "$input" in
	*"git push"*) ;;
	*) exit 0 ;;
esac
case "$input" in
	*--force*|*" -f "*) ;;
	*) exit 0 ;;
esac
case "$input" in
	*REWRITE_OK=1*) exit 0 ;;
esac

branch=$(sed -n 's/.*git push[^|;]*origin[[:space:]]\{1,\}\([A-Za-z0-9._/-]\{1,\}\).*/\1/p' <<< "$input" | head -1)
[ -n "$branch" ] || exit 0
git rev-parse --verify --quiet "$branch" > /dev/null || exit 0

based=$(git branch --format='%(refname:short)' --contains "$branch" | grep -vx "$branch")
[ -n "$based" ] || exit 0

{
	echo "rewrite-guard: these branches are based on '$branch' and keep what this push drops:"
	for b in $based; do
		echo "  $b"
	done
	echo "rewrite-guard: rebase them onto the rewritten branch, or re-run with REWRITE_OK=1 once that list is stale."
} >&2
exit 2

