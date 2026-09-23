#!/bin/bash
# Reports the state of the open pull requests, so a claim about them is read
# rather than remembered: base, mergeability, commit count and how many of those
# are unsquashed fixups, the size, the CI conclusion, the labels the review
# workflows leave behind, and the merged pull request that names it as the one
# it replaced ("Alternative to #N" in the body), which is one to close.
#
# A pull request based on another branch names the pull request of that base:
# after:#N while it is open, base-merged:#N once it merged, which means the
# stacked one is retargeted to the default branch and restacked before it is
# merged (the merged skill), or GitHub merges it into the stale base.
#
# With --ready, lists only what a maintainer can pick up: reviewed by a workflow,
# green on CI, no unsquashed fixup, mergeable as GitHub has computed it, based on
# the default branch, and not replaced by a merged one.
#
# Usage: GH_TOKEN=... bash tools/pr-status.sh [--ready] [<number>...]

repo=${LUNATIK_REPO:-luainkernel/lunatik}
fmt='%-6s %-26s %-24s %-5s %-7s %-11s %-9s %s\n'

ready=0
[ "$1" = "--ready" ] && { ready=1; shift; }
numbers="$*"
[ -n "$numbers" ] || numbers=$(gh api "repos/$repo/pulls" --paginate -q '.[].number' | sort -n)
default=$(gh api "repos/$repo" -q .default_branch)

printf "$fmt" PR BRANCH BASE COMM FIXUPS SIZE CI LABELS
for n in $numbers; do
	pr=$(gh api "repos/$repo/pulls/$n" \
		-q '[.head.ref, .base.ref, (.commits|tostring), (.mergeable|tostring), "+\(.additions)/-\(.deletions)", .head.sha, (if .merged_at then "merged" else .state end), ([.labels[].name] | join(",") // "")] | @tsv') || continue
	IFS=$'\t' read -r branch base commits mergeable size sha state labels <<< "$pr"
	if [ "$state" != open ]; then
		[ "$ready" = 1 ] || printf "$fmt" "#$n" "$branch" "$base" - - - - "$state"
		continue
	fi
	fixups=$(gh api "repos/$repo/pulls/$n/commits" \
		-q '[.[] | select(.commit.message | startswith("fixup!"))] | length')
	ci=$(gh api "repos/$repo/commits/$sha/check-runs" \
		-q '[.check_runs[].conclusion] | if length == 0 then "none" else (unique | join(",")) end' 2>/dev/null)
	superseded=$(gh api -X GET search/issues -f q="repo:$repo is:pr is:merged \"Alternative to #$n\"" \
		-q "[.items[].number | select(. != $n) | \"#\\(.)\"] | join(\",\")" 2>/dev/null)

	stack=""
	[ "$base" = "$default" ] || stack=$(gh api "repos/$repo/pulls?head=${repo%%/*}:$base&state=all" \
		-q '.[0] // empty | if .merged_at then "base-merged:#\(.number)" else "after:#\(.number)" end' 2>/dev/null)

	if [ "$ready" = 1 ]; then
		[ "$mergeable" = "true" ] && [ "$fixups" = 0 ] && [ "$ci" = "success" ] && [ -z "$superseded" ] &&
			[ "$base" = "$default" ] || continue
		case "$labels" in *workflow-reviewed*) ;; *) continue ;; esac
	fi
	case "$mergeable" in true) ;; null) base="$base(?)" ;; *) base="$base(!)" ;; esac
	printf "$fmt" "#$n" "$branch" "$base" "$commits" "$fixups" "$size" "$ci" "${labels:--}${superseded:+ superseded-by:$superseded}${stack:+ $stack}"
done

