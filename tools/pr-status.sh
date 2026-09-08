#!/bin/bash
# Reports the state of the open pull requests, so a claim about them is read
# rather than remembered: base, mergeability, commit count and how many of those
# are unsquashed fixups, the CI conclusion, and the labels the review workflows
# leave behind. A pull request whose branch is not fetched shows its state as
# GitHub has it and nothing more.
#
# Usage: GH_TOKEN=... bash tools/pr-status.sh [<number>...]

repo=${LUNATIK_REPO:-luainkernel/lunatik}
numbers="$*"
[ -n "$numbers" ] || numbers=$(gh api "repos/$repo/pulls" --paginate -q '.[].number' | sort -n)

printf '%-6s %-26s %-24s %-5s %-7s %-11s %-9s %s\n' PR BRANCH BASE COMM FIXUPS SIZE CI LABELS
for n in $numbers; do
	read -r branch base commits mergeable size < <(gh api "repos/$repo/pulls/$n" \
		-q '"\(.head.ref) \(.base.ref) \(.commits) \(.mergeable) +\(.additions)/-\(.deletions)"')
	fixups=$(gh api "repos/$repo/pulls/$n/commits" \
		-q '[.[] | select(.commit.message | startswith("fixup!"))] | length')
	labels=$(gh api "repos/$repo/pulls/$n" -q '[.labels[].name] | join(",")')
	sha=$(gh api "repos/$repo/pulls/$n" -q .head.sha)
	ci=$(gh api "repos/$repo/commits/$sha/check-runs" \
		-q '[.check_runs[].conclusion] | if length == 0 then "none" else (unique | join(",")) end' 2>/dev/null)
	[ "$mergeable" = "true" ] || base="$base(!)"
	printf '%-6s %-26s %-24s %-5s %-7s %-11s %-9s %s\n' "#$n" "$branch" "$base" "$commits" "$fixups" "$size" "$ci" "${labels:--}"
done

