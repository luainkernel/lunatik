#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a message git commit takes from an editor is cleaned in strip mode, which
# drops every line that opens with '#', so a body line that opens with an issue's number vanishes
# without a word; one -F reads with no editor is cleaned in whitespace mode and keeps it. This blocks
# (exit 2) a git commit whose editor copies in a file, GIT_EDITOR="cp <file>", or that edits the file
# -F reads, -e, when that file holds such a line and no --cleanup keeps it, unless the command
# carries MESSAGE_OK=1; silent (exit 0) on everything else. Reads the command field of the raw hook
# input through commands.sh, and the file where the command names it.

input=$(cat)

case "$input" in
	*"git "*commit*) ;;
	*) exit 0 ;;
esac

command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
case "$command" in
	*MESSAGE_OK=1*|*--cleanup=whitespace*|*--cleanup=verbatim*|*--cleanup=scissors*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

# git past its global options, as push-guard.sh reads it
git='^([^ ]*/)?git( -C [^ ]+| -c [^ =]+=([^ -][^ ]*( [^ -][^ ]*)*)?| -[^ ]+)*'
commits=$(commands "$input" | grep -E "$git commit( |\$)") || exit 0

# the files the commit's editor holds: the one GIT_EDITOR copies in, and the one -F reads under -e
files=$(printf '%s' "$command" | sed -nE "s/.*GIT_EDITOR=[\"']?cp ([^ \"']+).*/\1/p")
files="$files $(printf '%s\n' "$commits" | grep -E ' (-e|--edit)( |$)' | sed -nE 's/.* (-F ?|--file[= ])([^ ]+).*/\2/p')"

for file in $files; do
	[ -r "$file" ] && grep -q '^#' "$file" || continue
	echo "message-guard: $file holds a line that opens with '#', which the editor's strip cleanup drops from the message: open it otherwise, or pass --cleanup=whitespace to keep it. MESSAGE_OK=1 commits it as git cleans it." >&2
	exit 2
done
exit 0

