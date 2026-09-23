#!/usr/bin/env bash
# PreToolUse (Workflow) hook: the effort is why an agent runs through a workflow here, so a script
# whose agent() calls name none runs every agent at the session's default, the mistake agent-guard.sh
# exists for. Blocks (exit 2) a workflow script, inline or by scriptPath, that calls agent() and never
# says effort; a script that names it once, in a wrapper or in a shorthand property, passes. Reads the
# tool call on stdin.

input=$(cat)

script=$input
path=$(printf '%s' "$input" | grep -oE '"scriptPath"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 |
	sed -E 's/.*"([^"]*)"$/\1/')
[ -n "$path" ] && [ -r "$path" ] && script=$(cat "$path")

printf '%s' "$script" | grep -qE '(^|[^[:alnum:]_.])agent\(' || exit 0
printf '%s' "$script" | grep -qE '(^|[^[:alnum:]_])effort([^[:alnum:]_]|$)' && exit 0

echo "workflow-effort-guard: every agent() names its effort, agent(PROMPT, {model: '<model>', effort: '<effort>'}); one without it runs at the session's default." >&2
exit 2

