#!/bin/bash
# Reports the state of the open pull requests, so a claim about them is read
# rather than remembered: base, mergeability, commit count and how many of those
# are unsquashed fixups, the size, the CI conclusion, and the labels the review
# workflows leave behind.
#
# With --ready, lists only what a maintainer can pick up: reviewed by a workflow,
# green on CI, no unsquashed fixup, and mergeable as GitHub has computed it.
#
# Usage: GH_TOKEN=... bash tools/pr-status.sh [--ready] [<number>...]

repo=${LUNATIK_REPO:-luainkernel/lunatik}
fmt='%-6s %-26s %-24s %-5s %-7s %-11s %-9s %s\n'

ready=0
[ "$1" = "--ready" ] && { ready=1; shift; }
numbers="$*"
[ -n "$numbers" ] || numbers=$(gh api "repos/$repo/pulls" --paginate -q '.[].number' | sort -n)

printf "$fmt" PR BRANCH BASE COMM FIXUPS SIZE CI LABELS
for n in $numbers; do
	pr=$(gh api "repos/$repo/pulls/$n" \
		-q '[.head.ref, .base.ref, (.commits|tostring), (.mergeable|tostring), "+\(.additions)/-\(.deletions)", .head.sha, ([.labels[].name] | join(",") // "")] | @tsv') || continue
	IFS=$'\t' read -r branch base commits mergeable size sha labels <<< "$pr"
	fixups=$(gh api "repos/$repo/pulls/$n/commits" \
		-q '[.[] | select(.commit.message | startswith("fixup!"))] | length')
	ci=$(gh api "repos/$repo/commits/$sha/check-runs" \
		-q '[.check_runs[].conclusion] | if length == 0 then "none" else (unique | join(",")) end' 2>/dev/null)

	if [ "$ready" = 1 ]; then
		[ "$mergeable" = "true" ] && [ "$fixups" = 0 ] && [ "$ci" = "success" ] || continue
		case "$labels" in *workflow-reviewed*) ;; *) continue ;; esac
	fi
	case "$mergeable" in true) ;; null) base="$base(?)" ;; *) base="$base(!)" ;; esac
	printf "$fmt" "#$n" "$branch" "$base" "$commits" "$fixups" "$size" "$ci" "${labels:--}"
done

