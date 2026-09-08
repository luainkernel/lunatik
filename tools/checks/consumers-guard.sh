#!/bin/bash
# PreToolUse (Bash) hook: a pull request that changes a binding is not opened
# before the out-of-tree scripts that load it were read. Reads the tool command
# on stdin, runs consumers.sh over the branch's own diff, and blocks (exit 2)
# when a consumer turns up, unless the command carries CONSUMERS_OK=1, set once
# they were read. Silent when LUNATIK_CONSUMERS is unset or nothing matches.

input=$(cat)

case "$input" in
	*"gh api"*pulls*) ;;
	*) exit 0 ;;
esac
case "$input" in
	*"-X POST"*|*"-X PATCH"*) ;;
	*) exit 0 ;;
esac
case "$input" in
	*CONSUMERS_OK=1*) exit 0 ;;
esac

dir=$(printf '%s' "$input" | grep -oE 'cd [^ ]+' | head -1 | cut -d' ' -f2)
[ -d "$dir" ] || dir="$CLAUDE_PROJECT_DIR"
[ -d "$dir" ] || exit 0

files=$(git -C "$dir" diff --name-only origin/master...HEAD 2>/dev/null)
[ -n "$files" ] || exit 0

report=$(cd "$dir" && bash "$CLAUDE_PROJECT_DIR/tools/checks/consumers.sh" $files)
[ -n "$report" ] || exit 0

echo "$report" >&2
echo "consumers-guard: read them, then re-run with CONSUMERS_OK=1 as a command prefix." >&2
exit 2

