#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What a pull request still needed after the review workflow read it, which is what the review
# missed or what the maintainer asked for over it: for each pull request labelled workflow-reviewed,
# the commits authored after the label and the comments written after it by a person, the ones that
# do not open with the line an agent's post carries. A review that left nothing to ask shows zeros
# there, and the totals say how often that was so. The forced pushes after it are shown beside them,
# and count nothing, since the squash before a merge is one.
#
# Usage: GH_TOKEN=... bash tools/review-stat.sh [<pr>...]   (default every labelled pull request)

repo=luainkernel/lunatik
label=workflow-reviewed

prs=$*
[ -n "$prs" ] || prs=$(gh api --paginate "repos/$repo/issues?state=all&labels=$label&per_page=100" --jq '.[].number')

printf '%-6s %-7s %7s %7s %8s  %s\n' PR STATE COMMITS PUSHES COMMENTS TITLE
total=0 clean=0
for pr in $prs; do
	at=$(gh api --paginate "repos/$repo/issues/$pr/events?per_page=100" \
		--jq "[.[] | select(.event == \"labeled\" and .label.name == \"$label\") | .created_at][0] // empty")
	[ -n "$at" ] || continue
	timeline=$(gh api --paginate -H 'Accept: application/vnd.github+json' "repos/$repo/issues/$pr/timeline?per_page=100" --jq '.[]' | jq -s .)
	# a rebase rewrites the committer date and keeps the author's, so a commit is dated by its author
	commits=$(jq --arg at "$at" '[.[] | select(.event == "committed" and .author.date > $at)] | length' <<<"$timeline")
	pushes=$(jq --arg at "$at" '[.[] | select(.event == "head_ref_force_pushed" and .created_at > $at)] | length' <<<"$timeline")
	comments=$( { gh api --paginate "repos/$repo/issues/$pr/comments?per_page=100" --jq '.[]'
		gh api --paginate "repos/$repo/pulls/$pr/comments?per_page=100" --jq '.[]'
		gh api --paginate "repos/$repo/pulls/$pr/reviews?per_page=100" --jq '.[] | select(.body != "") | .created_at = .submitted_at'; } |
		jq -s --arg at "$at" '[.[] | select(.created_at > $at and .user.type != "Bot" and (.body | startswith("(posted by an agent") | not))] | length')
	read -r state title < <(gh api "repos/$repo/pulls/$pr" --jq '"\(if .merged_at then "merged" else .state end) \(.title)"')
	printf '%-6s %-7s %7s %7s %8s  %s\n' "#$pr" "$state" "$commits" "$pushes" "$comments" "${title:0:60}"
	total=$((total + 1))
	[ "$commits$comments" = 00 ] && clean=$((clean + 1))
done
echo "$clean of $total reviewed pull requests needed nothing after the review"

