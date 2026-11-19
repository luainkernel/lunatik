#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a cd the session runs into a directory of the checkout stays its working
# directory for every later call, and Claude Code's own check refuses to remove the session's working
# directory, so the rm -rf that ends a scratch worktree fell to the maintainer as a script. This blocks
# (exit 2) a shell call whose working directory, the cwd field of the hook input, which follows the
# session's cd, lies under CLAUDE_PROJECT_DIR other than its root, unless the call opens with a cd back
# to the root; silent (exit 0) at the root, outside it, under .claude/worktrees, where Claude Code puts
# a worktree the session enters on purpose, in a subagent, whose cd lasts one call (the input carries
# agent_id), and where CLAUDE_PROJECT_DIR is unset.

input=$(cat)
root=${CLAUDE_PROJECT_DIR:-}
cwd=$(printf '%s' "$input" | jq -r 'if .agent_id then empty else .cwd // empty end')
[ -n "$root" ] && [ -n "$cwd" ] || exit 0

case "$cwd/" in
	"$root/"|"$root"/.claude/worktrees/*) exit 0 ;;
	"$root"/*) ;;
	*) exit 0 ;;
esac

case "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" in
	"cd $root"|"cd $root "*|"cd \"$root\""|"cd \"$root\" "*) exit 0 ;;
esac

echo "cd-guard: the session's working directory is $cwd, where a cd left it: Claude Code keeps it for every later call and refuses to remove it, so a worktree removed from there falls to the maintainer. Run cd $root as a command of its own, then reach the directory with git -C, make -C or ( cd <dir> && ... )." >&2
exit 2

