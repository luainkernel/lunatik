#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Lists the commits a base took since an issue was opened that touch the files the issue names, so
# an issue the tree answered after it was filed is read as answered before an agent is launched on
# it: four issues of a batch on 2026-11-04, each saying no case covered something, were declined by
# their groomers after the launch, the cases having landed days after the issues were filed. A file
# the issue names is a path under a top-level directory of the tree, or a root source, in its body,
# with a `:line` suffix dropped; one the base does not hold is listed apart. The commits are read,
# not obeyed: one that touches a named file need not answer the issue.
#
# Usage: GH_TOKEN=... bash tools/issue-since.sh <issue> [<base>]   (base: origin/master, as fetched)

repo=${LUNATIK_REPO:-luainkernel/lunatik}
issue=$1
base=${2:-origin/master}
[ -n "$issue" ] || { echo "usage: $0 <issue> [<base>]" >&2; exit 2; }

created=$(gh api "repos/$repo/issues/$issue" -q .created_at) || exit 1
title=$(gh api "repos/$repo/issues/$issue" -q .title)
body=$(gh api "repos/$repo/issues/$issue" -q .body)

top='lib|tests|tools|examples|bin|autogen|common|doc|include|\.agents|\.github'
named=$(grep -oE "(^|[^A-Za-z0-9_./-])(($top)/[A-Za-z0-9_./-]*[A-Za-z0-9_]|lunatik[A-Za-z0-9_]*\.[ch]|Makefile|Kbuild|driver\.lua)" <<< "$body" \
	| sed -E 's/^[^A-Za-z.]//' | sort -u)

held=() gone=()
for path in $named; do
	if git cat-file -e "$base:$path" 2> /dev/null; then held+=("$path"); else gone+=("$path"); fi
done

echo "#$issue $title (opened $created)"
echo "names: ${held[*]:-none on $base}"
[ ${#gone[@]} -eq 0 ] || echo "not on $base: ${gone[*]}"
[ ${#held[@]} -gt 0 ] || exit 0
commits=$(git log --oneline --no-merges --since="$created" "$base" -- "${held[@]}")
if [ -n "$commits" ]; then
	echo "commits since, to read against the issue:"
	echo "$commits"
else
	echo "no commit since touched them"
fi

