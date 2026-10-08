#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# UserPromptSubmit adapter: reads the maintainer's message through tools/checks/question.sh and, when
# it asks rather than directs, adds to the turn that it answers and changes nothing; the check is a
# plain path-taking script (.agents/rules/checks.md), this only translates.

input=$(cat)
command -v jq > /dev/null || exit 0

prompt=$(mktemp) || exit 0
trap 'rm -f "$prompt"' EXIT
printf '%s' "$input" | jq -r '.prompt // empty' > "$prompt"
# a background task's notification reaches the turn as a prompt, and the maintainer wrote none of it
grep -q '^<task-notification>' "$prompt" && exit 0
[ -n "$(bash "$(dirname "$0")/../../tools/checks/question.sh" "$prompt")" ] || exit 0

jq -cn --arg ctx '[question] The maintainer asked, and did not direct: this turn answers, and changes nothing. No edit, commit, push, workflow, agent or GitHub write until he says to; a step the answer recommends is proposed with its decision, not taken.' \
	'{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
exit 0

