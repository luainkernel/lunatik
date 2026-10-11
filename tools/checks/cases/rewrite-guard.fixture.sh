#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository rewrite-guard.cases reads. Each branch <b> has the
# head the remote holds, tagged <b>.old, and the head a restack made, tagged <b>.new; origin/<b> is its
# remote-tracking ref where it has one, and <b>-dep a branch based on one of the two heads.
#
# Usage: bash tools/checks/cases/rewrite-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
git init -q -b master . && git commit -q --allow-empty -m root || exit 1

# a commit with <message> on <parent>, printed
commit() {
	git commit-tree -p "$2" -m "$1" "$(git rev-parse "$2^{tree}")"
}

for b in restacked kept local detached ahead; do
	git tag "$b.old" "$(commit "$b" master)"
	git tag "$b.new" "$(commit "$b rebased" master)"
done

# the restack moved the branch to its new head and rebased the one based on it
git branch restacked restacked.new
git branch restacked-dep "$(commit dep restacked.new)"
git update-ref refs/remotes/origin/restacked restacked.old

# the branch moved and the one based on it did not, checked out in on-kept
git branch kept kept.new
git branch kept-dep "$(commit dep kept.old)"
git update-ref refs/remotes/origin/kept kept.old
git worktree add -q on-kept kept

# the branch still on the head the push replaces, with no remote-tracking ref
git branch local local.old
git branch local-dep "$(commit dep local.old)"

# the worktree detached on a commit based on the head the push replaces, which no branch holds
git branch detached detached.new
git checkout -q --detach "$(commit scratch detached.old)"

# a fixup on the head the remote holds
git branch ahead "$(commit fixup ahead.old)"
git branch ahead-dep "$(commit dep ahead.old)"
git update-ref refs/remotes/origin/ahead ahead.old

