#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What a review reads before it judges a change, gathered once by the machine: the commits with
# their bodies, the files they touch, the diff with every function it touches whole, and what the
# checks say about it. A reviewer that gathers the same with its own reads pays for each of them on
# every turn after.
#
# Usage: bash tools/review-packet.sh <base> <head>   (in a worktree checked out at <head>)

base=$1
head=$2
[ -n "$base" ] && [ -n "$head" ] || { echo "usage: review-packet.sh <base> <head>" >&2; exit 2; }
dir=$(dirname "$0")

echo "# Commits"
git log --reverse --format='## %h %s%n%n%b' "$base..$head"

echo "# Files"
git diff --stat=120 "$base" "$head"

echo "# Checks"
bash "$dir/checks/advisory.sh" "$base" "$head"
for check in author-email body-identifiers; do
	out=$(bash "$dir/checks/$check.sh" "$base..$head" 2>&1)
	[ -n "$out" ] && printf '== %s\n%s\n' "$check" "$out"
done

# the submodules are gitlinks here, and their diff is the fork's own history
echo "# Diff"
git diff --function-context "$base" "$head" -- . ':!lua' ':!klibc' ':!luac'
git diff --submodule=log "$base" "$head" -- lua klibc luac

