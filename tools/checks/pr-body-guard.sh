#!/usr/bin/env bash
# PreToolUse (Bash) hook: a pull request body is posted only when pr-body.sh passes on
# it. This blocks (exit 2) a gh write to pulls that carries a body file (-F body=@file)
# the check fails on, printing the findings; silent (exit 0) on everything else.
# Matches the raw hook input, which embeds the command verbatim.

input=$(cat)

case "$input" in
	*"gh api"*pulls*"body=@"*|*"gh pr create"*"--body-file"*|*"gh pr edit"*"--body-file"*) ;;
	*) exit 0 ;;
esac

file=$(printf '%s' "$input" | sed -n 's/.*body=@\([^ "\\]*\).*/\1/p; s/.*--body-file[ =]\([^ "\\]*\).*/\1/p' | head -1)
[ -n "$file" ] && [ -f "$file" ] || exit 0

findings=$(bash "$(dirname "$0")/pr-body.sh" "$file")
[ -z "$findings" ] && exit 0

echo "pr-body-guard: $findings" >&2
exit 2

