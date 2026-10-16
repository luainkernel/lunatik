#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# SessionStart adapter, after a compaction: what the session corrected before it survives only in the
# summary, and a compacted session removed a crash guard on the host, recommended a model by precedent,
# cited a rule it had not read and asked the maintainer what the conventions settle. This prints those
# rules into the context as the tree states them now, each read from its file by the words it opens
# with, so the hook keeps no copy of them; a rule it cannot find is named instead.

root="$(dirname "$0")/../.."
rules='AGENTS.md|1. **Verify, do not assume.**
AGENTS.md|* A step the session can take it takes.
AGENTS.md|* A call the conventions here already settle is made, not escalated
AGENTS.md|* "The tree does it" is a fact about the tree, not a reason.
.agents/rules/tests.md|* a test that guards a kernel crash is not proved by removing the guard'

echo "The session was compacted: what it corrected before survives only in the summary. These rules, read from the tree now, are the ones a compacted session broke:"
while IFS='|' read -r file opening; do
	rule=$(awk -v opening="$opening" '
		!found && index($0, opening) == 1 { found = 1; print; next }
		found && (/^[[:space:]]*$/ || /^\* / || /^[0-9]+\. /) { exit }
		found { print }' "$root/$file" 2> /dev/null)
	if [ -n "$rule" ]; then
		printf '\n%s:\n%s\n' "$file" "$rule"
	else
		printf '\nThe rule opening with "%s" is not in %s; .claude/hooks/on-compact.sh names it.\n' "$opening" "$file"
	fi
done <<< "$rules"
exit 0

