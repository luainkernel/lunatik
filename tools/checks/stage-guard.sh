#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a commit is staged by purpose, never by working tree. Staging everything
# at the end of an edit that touched several concerns fuses them into one commit, and the message
# then explains part of what it carries. This blocks (exit 2) a git add of the whole tree, -A,
# --all, -u, --update, . or :/, and a git commit -a, unless the command carries STAGE_OK=1; silent
# (exit 0) on everything else. Reads the command field of the raw hook input through commands.sh.

input=$(cat)

case "$input" in
	*"git "*add*|*"git "*commit*) ;;
	*) exit 0 ;;
esac

# the marker counts in the command, not in its description
case "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" in
	*STAGE_OK=1*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

# git past its global options, as push-guard.sh reads it
git='^([^ ]*/)?git( -C [^ ]+| -c [^ =]+=([^ -][^ ]*( [^ -][^ ]*)*)?| -[^ ]+)*'
whole=" (-A|--all|-u|--update|\\.|:/)( |\$)"
printf '%s\n' "$(commands "$input")" |
	grep -Eq "$git add( [^ ]+)*$whole|$git commit( [^ ]+)* (-a|--all|-[a-zA-Z]*a[a-zA-Z]*)( |\$)" || exit 0

echo "stage-guard: stage by purpose: name the files of one change (git add <paths>), read git diff --cached against the message, then commit; STAGE_OK=1 stages a tree that holds one change only." >&2
exit 2

