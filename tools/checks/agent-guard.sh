#!/usr/bin/env bash
# PreToolUse (Agent) hook: an agent that works on this tree runs through the Workflow tool, whose
# agent() takes the model and the reasoning effort; the Agent tool takes a model and no effort, so
# what it launches runs at the default effort whatever was asked. Blocks (exit 2) every Agent call
# but a read-only search (Explore) and the Claude Code guide. Reads the tool call on stdin.

input=$(cat)

# the key of the tool input, not the escaped quote of one inside a prompt
type=$(printf '%s' "$input" | grep -oE '(^|[^\\])"subagent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 |
	sed -E 's/.*"([^"]*)"$/\1/')
case "$type" in
	Explore|claude-code-guide) exit 0 ;;
esac

{
	echo "agent-guard: an agent runs through the Workflow tool, where agent() takes the effort the Agent tool cannot:"
	echo "  export const meta = {name: '<name>', description: '<one line>'}"
	echo "  return await agent(PROMPT, {model: '<model>', effort: '<effort>'})"
} >&2
exit 2

