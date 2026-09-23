#!/bin/bash
# Reports the issues an epic tracks as GitHub has them, so what a merge closed is read rather
# than remembered: the epic and each issue whose body says it is part of it, its state, and the
# pull requests whose body names it, open or merged, with what each body does to it. An issue
# closes, and its card on the project board moves with it, only when a merged pull request
# closes it with a keyword or someone closes it by hand, so this flags an open issue a merged
# pull request names, and a merged pull request tied to an issue in the words pr-body.sh reads
# that closes none and does not say which it leaves open (tools/checks/closing.sh has the forms).
#
# Usage: GH_TOKEN=... bash tools/issues.sh <epic number>

. "$(dirname "$0")/checks/closing.sh"

repo=${LUNATIK_REPO:-luainkernel/lunatik}
epic=$1
[ -n "$epic" ] || { echo "usage: $0 <epic number>"; exit 1; }

# the epic, then the issues whose body says they are part of it: number, state, title
members() {
	gh api "repos/$repo/issues/$epic" -q '[.number, .state, .title] | @tsv'
	gh api --paginate "repos/$repo/issues/$epic/timeline?per_page=100" -q "
		.[] | select(.event == \"cross-referenced\") | .source.issue
		| select(.pull_request == null and .repository.full_name == \"$repo\")
		| select((.body // \"\") | test(\"Part of[^.#]*#$epic([^0-9]|\$)\"))
		| [.number, .state, .title] | @tsv" | sort -un
}

# the pull requests whose body names issue $1: number, state, and what the body does to it
namers() {
	gh api --paginate "repos/$repo/issues/$1/timeline?per_page=100" -q "
		.[] | select(.event == \"cross-referenced\") | .source.issue
		| select(.pull_request != null and .repository.full_name == \"$repo\")
		| (.body // \"\") as \$body | select(\$body | test(\"#$1([^0-9]|\$)\"))
		| [.number, (if .pull_request.merged_at then \"merged\" else .state end),
			if (\$body | test(\"$(closes "$1")\"; \"i\")) then \"closes it\"
			elif (\$body | test(\"$(leaves "$1")\"; \"i\")) then \"leaves it open\"
			elif (\$body | test(\"$(closes)|$(leaves)\"; \"i\")) then \"closes another\"
			elif (\$body | test(\"$(ties)\")) then \"closes nothing\"
			else \"names it\" end] | @tsv" | sort -un
}

members | while IFS=$'\t' read -r n state title; do
	printf 'issue\t%s\t%s\t%s\n' "$n" "$state" "$title"
	namers "$n" | sed "s/^/pr\t$n\t/"
done | awk -F'\t' -v epic="$epic" '
	$1 == "issue" {
		printf "#%-6s %-7s %s\n", $2, $3, $4
		state[$2] = $3
	}
	$1 == "pr" {
		printf "        #%s %s, %s\n", $3, $4, $5
		if ($4 == "merged" && $5 == "closes nothing")
			flag["#" $3 " merged, tied to an issue, and closes none"]
		if ($4 == "merged" && state[$2] == "open" && $2 != epic && $5 != "leaves it open")
			flag["#" $2 " is open and #" $3 ", merged, names it"]
	}
	END {
		for (f in flag)
			print "flag: " f | "sort"
	}'

