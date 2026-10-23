#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: the session merges a pull request without the maintainer only when the
# posting account opened it on master, it changes the harness alone, removes nothing and leaves
# alone what this gate reads, and its head carries the agent-review status and passed every check
# run (AGENTS.md, "Patches and commits"). This blocks (exit 2) a gh write that merges a pull request
# other than by rebase, or one that GitHub, asked with the credential the command carries, does not
# answer is such a pull request, unless the command carries MERGE_OK=1, set when the maintainer
# ordered that merge in his own words; silent (exit 0) on everything else. Reads the command field
# of the raw hook input through commands.sh, as stacked-guard.sh does.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*"gh api"*merge*|*"gh pr "*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

# the marker counts in the command, not in its description
case "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" in
	*MERGE_OK=1*) exit 0 ;;
esac

cmds=$(commands "$input")
merges=$(gh_writes "$cmds" 'pr merge' '^(https://api\.github\.com)?/?repos/[^/]+/[^/]+/pulls/[0-9]+/merge$')
[ -n "$merges" ] || exit 0

# what this gate reads, which a change merged by the gate itself could widen
gate='^(\.claude/settings\.json|\.github/.*|tools/checks/(merge-guard|harness-mixed)\.sh)$'

refuse() {
	echo "merge-guard: $1. The session merges only a harness pull request review.js passed (AGENTS.md, \"Patches and commits\"); one the maintainer ordered merged in his own words takes MERGE_OK=1." >&2
	exit 2
}

token=$(gh_token "$input")
github() {
	GH_TOKEN=$token gh api "$@" 2>/dev/null
}

while IFS= read -r merge; do
	if [ "$(printf '%s' "$merge" | awk '{ print $2 }')" = pr ]; then
		printf '%s\n' "$merge" | grep -Eq -- ' (--rebase|-r)( |$)'
	else
		printf '%s\n' "$merge" | grep -Eq -- ' merge_method=rebase( |$)'
	fi || refuse "a pull request merges by rebase, as the maintainer's do and the merged skill reads them"

	repo=$(gh_repo "$merge")
	repo=${repo:-{owner\}/{repo\}}
	number=$(gh_number "$merge")
	read -r state base author head <<< "$(github "repos/$repo/pulls/$number" --jq '[.state, .base.ref, .user.login, .head.sha] | @tsv')"
	[ -n "$head" ] || refuse "GitHub did not answer for #$number"
	[ "$state" = open ] && [ "$base" = master ] || refuse "#$number is not open on master"
	[ "$author" = "$(github user --jq .login)" ] || refuse "#$number was not opened by the posting account"

	files=$(github "repos/$repo/pulls/$number/files?per_page=100" --paginate --jq '.[] | [.status, .filename, .previous_filename // ""] | @tsv')
	[ -n "$files" ] || refuse "GitHub did not answer for the files of #$number"
	removed=$(printf '%s\n' "$files" | awk -F'\t' '$1 == "removed" { print $2 }')
	[ -z "$removed" ] || refuse "#$number removes $(echo $removed)"
	paths=$(printf '%s\n' "$files" | awk -F'\t' '{ print $2; if ($3 != "") print $3 }')
	outside=$(printf '%s\n' "$paths" | bash "$(dirname "$0")/harness-mixed.sh" --outside)
	[ -z "$outside" ] || refuse "#$number changes what is not the harness: $(echo $outside)"
	gated=$(printf '%s\n' "$paths" | grep -E "$gate")
	[ -z "$gated" ] || refuse "#$number changes what this gate reads: $(echo $gated)"

	review=$(github "repos/$repo/commits/$head/status" --jq '.statuses[] | select(.context == "agent-review") | .state')
	[ "$review" = success ] || refuse "the head of #$number, ${head:0:9}, carries no agent-review status"
	checks=$(github "repos/$repo/commits/$head/check-runs?per_page=100" --jq '.check_runs[] | .conclusion // "pending"')
	[ -n "$checks" ] && ! printf '%s\n' "$checks" | grep -vqxE 'success|skipped|neutral' ||
		refuse "the CI of ${head:0:9} has not passed"
done <<< "$merges"

exit 0

