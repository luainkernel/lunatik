#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# UserPromptSubmit adapter: reads the maintainer's message through tools/checks/question.sh and, when
# it asks rather than directs, adds to the turn that it answers and changes nothing, and through
# tools/checks/table.sh and, when it asks for a table, how much a cell holds for the table to be drawn;
# the checks are plain path-taking scripts (.agents/rules/checks.md), this only translates.

input=$(cat)
command -v jq > /dev/null || exit 0

prompt=$(mktemp) || exit 0
trap 'rm -f "$prompt"' EXIT
printf '%s' "$input" | jq -r '.prompt // empty' > "$prompt"
# a background task's notification reaches the turn as a prompt, and the maintainer wrote none of it
grep -q '^<task-notification>' "$prompt" && exit 0

checks="$(dirname "$0")/../../tools/checks"
ctx=
[ -n "$(bash "$checks/question.sh" "$prompt")" ] &&
	ctx='[question] The maintainer asked, and did not direct: this turn answers, and changes nothing. No edit, commit, push, workflow, agent or GitHub write until he says to; a step the answer recommends is proposed with its decision, not taken.'
[ -n "$(bash "$checks/table.sh" "$prompt")" ] &&
	ctx="${ctx:+$ctx }"'[table] A table in the reply is drawn as one only while it fits: Claude Code wraps each cell to the width its column gets, and when a cell runs past four lines, or the table past the terminal, it prints every row as "Header: value" lines instead, which is not the table asked for. Each cell holds a few words, under 40 characters, in five columns at most; what does not fit goes in a list below the table, keyed by the first column.'
[ -n "$ctx" ] || exit 0

jq -cn --arg ctx "$ctx" \
	'{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
exit 0

