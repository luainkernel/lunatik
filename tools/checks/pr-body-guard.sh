#!/usr/bin/env bash
# PreToolUse (Bash) hook: a pull request body is posted only when pr-body.sh passes on
# it. This blocks (exit 2) a gh write to pulls that carries a body file (-F body=@file)
# the check fails on, printing the findings; silent (exit 0) on everything else.
# Reads the command field of the raw hook input through commands.sh: the description
# beside it and the commands chained with the write are not the write. The body file goes
# through machine-leak.sh first: a pull request body is text posted to GitHub like
# any other, so a body the guard cannot read, passed inline, is refused rather than skipped.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*"gh api"*pulls*body=*|*"gh pr create"*--body*|*"gh pr edit"*--body*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

# a review or a comment body is review-post-guard's, on an endpoint below the pull request's own
posts=$(gh_writes "$(commands "$input")" 'create|edit' '^(https://api\.github\.com)?/?repos/[^/]+/[^/]+/pulls(/[0-9]+)?$' |
	grep -E ' (--body(-file)?([ =]|$)|body=)')
[ -n "$posts" ] || exit 0

flag="(body=@|--body-file[ =])"
# the quotes gh is written with are not part of the path: skipped before it, excluded from it
file=$(printf '%s' "$posts" | grep -oE "$flag[\"'\\\\]*[^[:space:]\"'\\\\]+" | sed -E "s/^$flag[\"'\\\\]*//" | head -1)
if [ -z "$file" ]; then
	echo "pr-body-guard: the body of a pull request is read from a file: pass it as --body-file <file>." >&2
	exit 2
fi
if [ ! -f "$file" ]; then
	echo "pr-body-guard: the body of a pull request is read from a file, and $file is not one. A path written as a shell variable arrives here unexpanded: spell it out." >&2
	exit 2
fi

leaked=$(bash "$(dirname "$0")/machine-leak.sh" "$file")
if [ -n "$leaked" ]; then
	echo "pr-body-guard: the body carries what belongs to the machine it was written on:" >&2
	echo "$leaked" >&2
	echo "pr-body-guard: rewrite the line and re-run." >&2
	exit 2
fi

findings=$(bash "$(dirname "$0")/pr-body.sh" "$file")
[ -z "$findings" ] && exit 0

echo "pr-body-guard: $findings" >&2
exit 2

