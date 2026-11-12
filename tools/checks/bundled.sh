#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a branch whose commits change a C binding of lib/ and the compiler under bin/luaebpf
# together: the binding is a pull request of its own, and the compiler's is stacked on it. #2235
# bundled what skb:data() reads of a non-linear skb, in lib/luadata.c, lib/luaskb.c and
# lib/luatc.c, with the compiler's TC read, two commits in one pull request, and the maintainer
# asked "why we need all these changes on luadata and why they are all bundled into this luaebpf
# PR? ... it should at very least split into many PRs". The commits may each keep to one side,
# as #2235's did; the branch is what a reviewer reads, so the range is read whole.
#
# Reads a rev-range, not files, since a pull request is one: prints the binding's files and how
# many of the compiler's, and exits 1 when the range carries both. The Checks workflow fails a
# pull request it names, pr-prep runs it over origin/master..HEAD and a review's packet over the
# branch from its base.
#
# Usage: bash tools/checks/bundled.sh <base>..<head>

[ $# -eq 1 ] || { echo "usage: bundled.sh <base>..<head>" >&2; exit 2; }

files=$(git diff --name-only "${1%%..*}"..."${1##*..}") || exit 2
binding=$(grep -E '^lib/[^/]+\.[ch]$' <<< "$files")
compiler=$(grep -E '^bin/luaebpf/' <<< "$files")
[ -n "$binding" ] && [ -n "$compiler" ] || exit 0

echo "$1 changes a C binding, $(echo $binding), and the compiler, $(wc -l <<< "$compiler") files under bin/luaebpf/, together:"
echo "the binding is a pull request of its own, and the compiler's is stacked on it (AGENTS.md, Patches and commits)"
exit 1

