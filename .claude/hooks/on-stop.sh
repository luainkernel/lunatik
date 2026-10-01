#!/bin/bash
# Stop adapter: reads the reply a turn ends on through tools/checks/decision.sh and
# tools/checks/reboot-capture.sh and sends it back once when it hands the maintainer a decision
# without the question, the options and a recommendation, or asks for a reboot nothing captured
# for; the checks are plain path-taking scripts (AGENTS.md, "Checks"), this only translates.

input=$(cat)
command -v jq > /dev/null || exit 0
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = true ] && exit 0

reply=$(mktemp) || exit 0
trap 'rm -f "$reply"' EXIT
printf '%s' "$input" | jq -r '.last_assistant_message // empty' > "$reply"
if [ ! -s "$reply" ]; then
	transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
	[ -f "$transcript" ] || exit 0
	tail -n 200 "$transcript" | jq -rs '[.[] | select(.type == "assistant") | .message.content[]? |
		select(.type == "text") | .text] | last // empty' > "$reply" 2> /dev/null
fi
[ -s "$reply" ] || exit 0

checks="$(dirname "$0")/../../tools/checks"
findings=$(bash "$checks/decision.sh" "$reply"; bash "$checks/reboot-capture.sh" "$reply")
[ -n "$findings" ] || exit 0
jq -n --arg reason "${findings//$reply/the reply}" '{decision: "block", reason: $reason}'
exit 0

