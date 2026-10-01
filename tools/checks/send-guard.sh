#!/usr/bin/env bash
# PreToolUse (SendMessage) hook: an agent a workflow launched is not messaged while the workflow waits
# on it. The message resumes a copy of the agent from its transcript, and the copy runs beside the
# original, in its worktree and on the host: #1390's and #1294's implementers ran twice that way, two
# writers in one tree and two cycles against one device. Blocks (exit 2) a message to an agent whose
# transcript sits under the session's subagents/workflows/<run>/ and whose run's journal.jsonl holds no
# result for it yet; silent on every other recipient. Reads the tool call on stdin, and the session's
# directory from its transcript_path, the layout Claude Code writes; where that layout is not found the
# guard passes.

input=$(cat)

field() {
	printf '%s' "$input" | grep -oE "(^|[^\\\\])\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 |
		sed -E 's/.*"([^"]*)"$/\1/'
}

to=$(field to)
to=${to%% \[*}
transcript=$(field transcript_path)
[ -n "$to" ] && [ -n "$transcript" ] || exit 0

for agent in "${transcript%.jsonl}"/subagents/workflows/*/"agent-$to.jsonl"; do
	[ -f "$agent" ] || continue
	grep -qE "\"type\":\"result\",[^}]*\"agentId\":\"$to\"" "$(dirname "$agent")/journal.jsonl" 2>/dev/null && continue
	echo "send-guard: $to is an agent of a workflow that is still waiting on it, and a message to it resumes a copy that runs beside it, in its worktree and on the host: act on its result when it returns, or stop the workflow and relaunch it with notes." >&2
	exit 2
done
exit 0

