#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names each comment a person left on a pull request that no reply of the session answers: an inline
# comment whose thread holds no later reply of the session's, and a comment of the conversation or the
# body of a review that no later comment of the session quotes by its first line outside a quote. The
# session posts from the maintainer's account, so its own posts are told from his by the note each one
# opens with, "This comment was written by an LLM". An answer given in the session's chat is one the
# pull request does not carry: #2630's review asked whether the collector could be stopped in an scx
# callback, and the answer reached the chat alone.
# Usage: GH_TOKEN=... bash tools/checks/unanswered.sh <number>
# Prints each unanswered comment as <url>: <its first line>; exits 1 when there are any, 2 when GitHub
# could not be read.

repo=luainkernel/lunatik
pr=${1:?usage: unanswered.sh <number>}
set -o pipefail

inline=$(gh api --paginate "repos/$repo/pulls/$pr/comments?per_page=100" | jq -s add) || exit 2
talk=$(gh api --paginate "repos/$repo/issues/$pr/comments?per_page=100" | jq -s add) || exit 2
reviews=$(gh api --paginate "repos/$repo/pulls/$pr/reviews?per_page=100" | jq -s add) || exit 2

found=$(jq -rn --argjson inline "$inline" --argjson talk "$talk" --argjson reviews "$reviews" '
	def ours: .body | test("^> \\[!NOTE\\]\n> This [a-z]+ was written by an LLM");
	def first: .body | split("\n") | map(select(test("\\S"))) | ((map(select(test("^\\s*>") | not)) | .[0]) // .[0] // "") | sub("^\\s+"; "") | sub("\\s+$"; "");
	def root: .in_reply_to_id // .id;
	($inline | map(select(ours))) as $replies |
	($talk | map(select(ours))) as $quotes |
	($inline[] | select(ours | not) | . as $c
		| select([$replies[] | select(root == ($c | root) and .created_at > $c.created_at)] | length == 0)
		| "\(.html_url): \(first)"),
	(($talk | map(select(ours | not) | {url: .html_url, at: .created_at, body}))
		+ ($reviews | map(select((.body // "") | test("\\S")) | select(ours | not) | {url: .html_url, at: .submitted_at, body}))
		| .[] | . as $c | ($c | first) as $line
		| select([$quotes[] | select(.created_at > $c.at and (.body | contains("> " + $line)))] | length == 0)
		| "\(.url): \($line)")
') || exit 2

[ -z "$found" ] && exit 0
printf '%s\n' "$found"
exit 1

