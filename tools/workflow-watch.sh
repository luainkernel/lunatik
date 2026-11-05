#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Watches workflow runs for the session that launched them, as a Monitor's command: a line naming
# the agents each run has running as the watch starts, one when an agent of a run starts, returns or
# fails, read from the run's journal.jsonl, and one when the run has written nothing for IDLE
# seconds, naming each agent still running and the last entry of its log, so a request the provider
# never answered (`api-request`) reads apart from a command that waits on the host
# (`assistant Bash`). The journal has no line for the end of a run: the workflow's own notification
# says it, and the session stops the watch then.
#
# Usage: bash tools/workflow-watch.sh <run id>...

IDLE=900
EVERY=60
[ $# -gt 0 ] || { echo "usage: $0 <run id>..." >&2; exit 2; }

projects=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects

# a line the runner is still writing does not parse yet, and is read on the next pass
journal() {
	jq -cR 'fromjson? // empty' "$1/journal.jsonl"
}

# the calls whose last entry in the journal is a start, the retry of a failed one among them, each
# with the last entry of its agent's log
running() {
	journal "$1" | jq -rs 'map(select(.key)) | group_by(.key) | map(last)[]
		| select(.type == "started") | "\(.agentId) \(.label)"' |
	while read -r id label; do
		last=$(tail -n 1 "$1/agent-$id.jsonl" 2>/dev/null | jq -r '[.type,
			(.message.content? // [] | if type == "array" then map(select(.type == "tool_use") | .name) | join(",") else "" end)]
			| map(select(. != "")) | join(" ")')
		printf '; running %s (last: %s)' "$label" "${last:-no log}"
	done
}

dirs=()
for run in "$@"; do
	dir=$(find "$projects" -maxdepth 5 -type d -path '*/subagents/workflows/*' -name "$run" -print -quit)
	[ -n "$dir" ] && [ -f "$dir/journal.jsonl" ] || { echo "workflow-watch: no journal for $run" >&2; exit 2; }
	dirs+=("$dir")
done

declare -A seen idle
while true; do
	now=$(date +%s)
	for dir in "${dirs[@]}"; do
		run=$(basename "$dir")
		entries=$(journal "$dir")
		lines=$(grep -c . <<<"$entries")
		if [ -z "${seen[$run]}" ]; then # a re-armed Monitor would read a replay as new starts
			echo "$run: watching$(running "$dir")"
		elif [ "$lines" -gt "${seen[$run]}" ]; then
			jq -rs --arg run "$run" --argjson from "${seen[$run]}" '
				(map(select(.type == "started") | {key: .agentId, value: .label}) | from_entries) as $labels
				| to_entries[] | select(.key >= $from) | .value
				| select(.type == "started" or .type == "result" or .type == "failed")
				| "\($run): \(if .type == "result" then "returned" else .type end) \($labels[.agentId] // .agentId)"
			' <<<"$entries"
		fi
		seen[$run]=$lines

		newest=$(find "$dir" -maxdepth 1 -type f -printf '%T@\n' | sort -n | tail -n 1)
		quiet=$(( now - ${newest%.*} ))
		if [ "$quiet" -ge "$IDLE" ]; then
			[ -n "${idle[$run]}" ] || echo "$run: nothing written for ${quiet}s$(running "$dir")"
			idle[$run]=1
		elif [ -n "${idle[$run]}" ]; then
			echo "$run: writing again"
			unset "idle[$run]"
		fi
	done
	sleep "$EVERY"
done

