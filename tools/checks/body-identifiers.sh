#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A commit body written before a squash keeps describing what a folded fixup
# removed: #848's body explained a FSNOTIFY_GROUP_USER guard for a kernel range
# the fixup had dropped, and the re-read after the squash missed it. What a
# body names is what its reader will look for, so an identifier the body carries
# that appears neither in the commit's diff nor in the tree at that commit is
# read as such a leftover.
#
# This one reads commits, not files, since a body belongs to a commit. An
# identifier is a token with an underscore in it, which is how C names in this
# tree and in the kernel are spelled, and the tree it is looked up in leaves the
# design notes out, since a note that names a symbol is what kept #848's stale
# paragraph hidden. A kernel symbol the body cites for a behaviour the code does
# not call, synchronize_srcu behind a put that refuses to wait, is named as
# well: over the last 40 commits of master it names something on 13, kernel
# internals a body traces, so the report is read, not obeyed. Heuristic: it
# nudges the re-read after a squash, it does not rewrite.
#
# Usage: bash tools/checks/body-identifiers.sh <commit or range>...   (default HEAD)

status=0

for commit in $(git rev-list --no-walk "${@:-HEAD}"); do
	diff=$(git show --format= "$commit")
	missing=""
	for ident in $(git show -s --format=%b "$commit" | grep -oE '\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b' | sort -u); do
		grep -qwF "$ident" <<< "$diff" && continue
		git grep -qwF "$ident" "$commit" -- . ':!*.md' 2>/dev/null && continue
		missing="$missing  $ident
"
	done
	[ -n "$missing" ] || continue

	printf '%s "%s" names what neither its diff nor its tree carries:\n%s' \
		"${commit:0:9}" "$(git show -s --format=%s "$commit")" "$missing"
	status=1
done

exit $status

