#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a workflow's scratch directory holds every phase's checkpoints, defect
# patches and worktrees, and a phase removes its own worktree, never the directory beside it. The
# build of #2080's run removed scratch/b2066 whole under the runs in flight, and the next build found
# its defect patches gone (#2123). This blocks (exit 2) a recursive rm of scratch itself, of a path
# one component under it, or of everything such a path holds (a trailing /*), unless the command
# carries SCRATCH_OK=1; silent (exit 0) on everything else, a worktree two components down among
# them. Reads the command field of the raw hook input through commands.sh, so a target a variable
# holds arrives unexpanded and passes.

input=$(cat)

case "$input" in
	*rm*scratch*) ;;
	*) exit 0 ;;
esac

# the marker counts in the command, not in its description
case "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" in
	*SCRATCH_OK=1*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

roots=$(printf '%s\n' "$(commands "$input")" | awk '
	$1 ~ /(^|\/)rm$/ {
		recursive = 0
		for (i = 2; i <= NF; i++)
			if ($i == "--recursive" || $i ~ /^-[a-zA-Z]*[rR]/)
				recursive = 1
		for (i = 2; recursive && i <= NF; i++) {
			path = $i
			sub(/\/+$/, "", path)
			if ($i !~ /^-/ && path ~ /(^|\/)scratch(\/[^\/]+)?(\/\*)?$/)
				print path
		}
	}')
[ -n "$roots" ] || exit 0

echo "scratch-guard: $(printf '%s' "$roots" | tr '\n' ' ')is a workflow's scratch directory, where every phase keeps its checkpoints, defect patches and worktrees: remove your own worktree (rm -rf <scratch>/<tree> && git worktree prune), never the directory beside it; SCRATCH_OK=1 removes one known to hold nothing of another run's." >&2
exit 2

