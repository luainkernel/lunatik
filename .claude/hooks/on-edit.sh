#!/bin/bash
# PostToolUse (Write|Edit) adapter: run the tools/checks file checks over the
# edited file and hand their findings back through the hook protocol, so the
# model is nudged at edit time. The checks are plain path-taking scripts
# (AGENTS.md, "Checks"); this wrapper only translates.

input=$(cat)
file=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$file" ] && [ -f "$file" ] || exit 0

# the checks of the tree the file belongs to, which in a worktree is not the session's
dir=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)
[ -n "$dir" ] && [ -d "$dir/tools/checks" ] || exit 0

findings=$(for check in module-conventions test-harness cppcheck-tests; do
	bash "$dir/tools/checks/$check.sh" "$file" 2>&1
done; bash "$dir/tools/checks/guard-removed.sh" "$file" 2>&1)
[ -z "$findings" ] && exit 0

escaped=$(printf '%s' "$findings" | tr '"\t' "' " | sed ':a;N;$!ba;s/\n/\\n/g')
printf '{"decision":"block","reason":"%s"}\n' "$escaped"
exit 0

