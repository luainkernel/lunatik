#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Whether a reader with none of a change's history passed a pull request body: a lunatik-reader agent
# of one of the session's workflow runs left this text, the last its Write tool wrote, as review.js
# hands it, and answered verdict pass. Both are read from the agent's own transcript, which Claude Code
# keeps beside the session's, <session>/subagents/workflows/<run>/agent-<id>.jsonl, with
# agent-<id>.meta.json naming the agent's type, so no agent records a pass. pr-body-guard.sh refuses
# the session's post of a body none passed. The checks read the form of a body, and #2527's passed them
# all and reached the maintainer unreadable. A text changed after the read is one nobody read.
# Usage: body-read.sh <body file> <session transcript>   exits 0 when a reader passed this text, 1 otherwise

[ -f "$1" ] || { echo "body-read: no body file at $1" >&2; exit 2; }

for meta in "${2%.jsonl}"/subagents/workflows/*/agent-*.meta.json; do
	grep -qE '"agentType"[[:space:]]*:[[:space:]]*"lunatik-reader"' "$meta" 2> /dev/null || continue
	# the text, whatever newlines end it: a body gh api reads out of JSON ends in one
	jq -se --rawfile body "$1" 'def text: sub("\n+\\z"; "");
		def call($tool): [.[] | select(.type == "assistant") | .message.content[]? |
			select(.type == "tool_use" and .name == $tool) | .input] | last;
		(call("StructuredOutput") | .verdict) == "pass" and (call("Write") | .content | strings | text) == ($body | text)' \
		"${meta%.meta.json}.jsonl" > /dev/null 2>&1 && exit 0
done
exit 1

