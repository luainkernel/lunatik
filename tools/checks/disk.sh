#!/usr/bin/env bash
# A build stops with "No space left on device" halfway through autogen, and the install that
# follows fails unseen while the previous one stays in place; on the shared host it is the
# scratch worktrees, each with a build of its own, that fill the disk. Takes a threshold in MB
# (default 1024); prints the free space and the largest scratch worktrees and exits 1 below it,
# silent otherwise.

min=${1:-1024}
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
project=${common:+$(dirname "$common")}
project=${project:-${CLAUDE_PROJECT_DIR:-$PWD}}

free=$(df -Pm "$project" | awk 'NR == 2 { print $4 }')
[ "$free" -ge "$min" ] && exit 0

echo "disk: ${free} MB free under $project, below ${min} MB; a build or an install stops halfway there"
[ -d "$project/scratch/wt" ] && du -sm "$project"/scratch/wt/* 2>/dev/null | sort -rn | head -5 | sed 's|^|  |'
echo "disk: a worktree whose review is posted goes: rm -rf <tree> && git worktree prune, since git worktree remove refuses one with submodules"
exit 1

