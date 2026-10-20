#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A step only the maintainer can take reaches him as a script the session wrote under /tmp and the
# one short line that runs it, "! bash /tmp/<name>.sh" in Claude Code: a command spelled out in the
# reply is one he copies by hand, and the terminal wraps it where the copy breaks. On 2026-10-11 a
# reply handed him the delete of the 21 branches a merge left as one line of 600 characters. A write
# to GitHub is not such a step: the auto mode classifier lets it through once his go is in the
# conversation, and on 2026-10-20 two comments he had approved reached him as a script to run.
# Takes text files, a reply; when one hands him a command, a line opening with "! ", longer than 60
# characters or continued on the next, or a script under /tmp that writes to GitHub with gh and runs
# nothing as root, prints it and exits 1.
#
# Usage: bash tools/checks/handoff.sh <file>...

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	long=$(awk '/^[[:space:]]*! / {
		cmd = $0; sub(/^[[:space:]]+/, "", cmd); sub(/[[:space:]]+$/, "", cmd)
		if (length(cmd) > 60 || cmd ~ /\\$/)
			printf "%d: %s...\n", NR, substr(cmd, 1, 40)
	}' "$file")
	if [ -n "$long" ]; then
		printf '%s\n' "$long" | sed "s|^|$file:|"
		echo "$file: hands the maintainer a command to copy; write it to a script under /tmp and give him the line that runs it, ! bash /tmp/<name>.sh"
		status=1
	fi
	for script in $(grep -oE '! bash /tmp/[^[:space:]`]+\.sh' "$file" | sed 's/^! bash //' | sort -u); do
		[ -f "$script" ] && grep -qE '(^|[[:space:];&|(])gh[[:space:]]' "$script" && ! grep -qE '(^|[[:space:];&|(])sudo[[:space:]]' "$script" || continue
		echo "$file: hands the maintainer $script, which writes to GitHub; that write is the session's once he says to post: show the text, ask for his go and post it"
		status=1
	done
done
exit $status

