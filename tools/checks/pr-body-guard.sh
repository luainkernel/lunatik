#!/usr/bin/env bash
# PreToolUse (Bash) hook: a pull request body is posted only when pr-body.sh passes on
# it, and an issue body only when untraced.sh does, since the paragraphs and the Closes
# line are a pull request's. This blocks (exit 2) a gh write to pulls or issues whose
# body, a file named by -F body=@, --body-file, -F or --input, the check fails on,
# printing the findings; silent (exit 0) on everything else. It also blocks a write to
# GitHub whose text no guard reads, curl's and a GraphQL mutation's.
# Reads the command field of the raw hook input through commands.sh: the description
# beside it and the commands chained with the write are not the write. The body file goes
# through machine-leak.sh first: a body is text posted to GitHub like any other, so a
# body the guard cannot read, passed inline, is refused rather than skipped. An issue
# edit is read for the lines it adds to the body GitHub has, asked with the credential the
# command carries: what the reporter posted, a build log and its paths, is not the edit's
# to rewrite. The whole body is read when the current one cannot be.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*"gh api"*|*"gh pr "*|*"gh issue "*|*curl*api.github.com*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# the GraphQL mutations the skills run, none of which carries text a guard would read
textless='markPullRequestReadyForReview|createProjectV2|addProjectV2ItemById|linkProjectV2ToRepository'

# the body file <file> of the issue write <post> with the lines the issue already carries blank, so a
# finding keeps its line number; the whole file for a new issue or a body GitHub does not answer with
added() {
	local post=$1 file=$2 target repo number current
	target=$(printf '%s' "$post" | grep -oE 'repos/[^/[:space:]"]+/[^/[:space:]"]+/issues/[0-9]+' | head -n 1)
	if [ -n "$target" ]; then
		repo=$(printf '%s' "$target" | cut -d/ -f2-3)
		number=${target##*/}
	else
		repo='{owner}/{repo}'
		number=$(printf '%s' "$post" | awk '$2 == "issue" && $3 == "edit" && $4 ~ /^[0-9]+$/ { print $4 }')
	fi
	if [ -z "$number" ] || ! current=$(GH_TOKEN=$(gh_token "$input") gh api "repos/$repo/issues/$number" --jq .body 2>/dev/null); then
		cat "$file"
		return
	fi
	awk 'NR == FNR { sub(/\r$/, ""); seen[$0]; next } { sub(/\r$/, ""); print ($0 in seen) ? "" : $0 }' \
		<(printf '%s\n' "$current") "$file"
}

# each body among the writes <writes> goes through machine-leak.sh, then through the check <check>;
# with <added>, only what an edit adds to the body GitHub has
check() {
	local post body file shown scan leaked findings
	while IFS= read -r post; do
		[ -n "$post" ] || continue
		body=$(gh_body "$post")
		case $body in
		"")
			continue ;;
		inline)
			[ "$(printf '%s' "$post" | awk '{ print $2 }')" = api ] && body='-F body=@<file>' || body='--body-file <file>'
			echo "pr-body-guard: a body is read from a file: pass it as $body." >&2
			exit 2 ;;
		esac
		file=${body#* }
		if [ ! -f "$file" ]; then
			echo "pr-body-guard: a body is read from a file, and $file is not one. A path written as a shell variable arrives here unexpanded: spell it out." >&2
			exit 2
		fi

		shown=$file
		if [ "${body%% *}" = input ]; then # the JSON gh api sends: its other fields here, its body below
			if ! jq -e 'type == "object"' "$file" > /dev/null 2>&1; then
				echo "pr-body-guard: $file, the JSON the write sends, does not read as an object." >&2
				exit 2
			fi
			jq 'del(.body)' "$file" > "$tmp/fields"
			leaked=$(bash "$(dirname "$0")/machine-leak.sh" "$tmp/fields")
			if [ -n "$leaked" ]; then
				echo "pr-body-guard: the fields of $file carry what belongs to the machine they were written on:" >&2
				echo "${leaked//"$tmp/fields"/$file}" >&2
				exit 2
			fi
			jq -e 'has("body")' "$file" > /dev/null || continue
			jq -r .body "$file" > "$tmp/body"
			shown="$file .body"
			file=$tmp/body
		fi

		scan=$file
		[ -z "$3" ] || { scan=$tmp/added; added "$post" "$file" > "$scan"; }
		leaked=$(bash "$(dirname "$0")/machine-leak.sh" "$scan")
		findings=$(bash "$(dirname "$0")/$2" "$scan")
		leaked=${leaked//$scan/$shown}
		findings=${findings//$scan/$shown}
		if [ -n "$leaked" ]; then
			echo "pr-body-guard: the body carries what belongs to the machine it was written on:" >&2
			echo "$leaked" >&2
			echo "pr-body-guard: rewrite the line and re-run." >&2
			exit 2
		fi

		[ -z "$findings" ] && continue

		echo "pr-body-guard: $findings" >&2
		exit 2
	done <<< "$1"
}

# a write whose text no guard reads: curl to GitHub's API with a method other than GET or with data, which
# curl sends as a POST, and a GraphQL mutation other than the textless ones
unread() {
	local line query file names
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		if [ "$line" = curl ]; then
			echo "pr-body-guard: a write to GitHub goes through gh, where the guards read its text; curl is for reads." >&2
			exit 2
		fi
		query=$line
		# the quotes gh is written with are not part of the path: skipped before it, excluded from it
		file=$(printf '%s' "$line" | grep -oE "(query=@|--input[ =])[\"'\\\\]*[^[:space:]\"'\\\\]+" | head -n 1 |
			sed -E "s/^(query=@|--input[ =])[\"'\\\\]*//")
		if [ -n "$file" ] && ! query=$(cat "$file" 2>/dev/null); then
			echo "pr-body-guard: the GraphQL query is read from a file, and $file is not one." >&2
			exit 2
		fi
		printf '%s' "$query" | grep -qw mutation || continue
		names=$(printf '%s' "$query" | grep -oE '[A-Za-z][A-Za-z0-9]*[[:space:]]*\(' | tr -d '( \t' |
			grep -vxE "mutation|$textless" | sort -u | tr '\n' ' ')
		[ -z "$names" ] && continue
		echo "pr-body-guard: a GraphQL mutation that can carry text ($names) goes through gh's REST form instead, where the guards read it." >&2
		exit 2
	done <<< "$(printf '%s\n' "$1" | awk '
	$1 ~ /^([^ ]*\/)?curl$/ && /api\.github\.com/ {
		for (i = 2; i <= NF; i++)
			if ($i ~ /^(-X|--request)$/ && toupper($(i + 1)) != "GET" || $i ~ /^-X./ && toupper(substr($i, 3)) != "GET" ||
			    $i ~ /^--request=/ && toupper(substr($i, 11)) != "GET" ||
			    $i ~ /^(-d|--data|--data-[a-z]+|--json|-F|--form|--form-string|-T|--upload-file)(=|$)/ || $i ~ /^-[dFT]./) {
				print "curl"
				next
			}
	}
	$1 ~ /^([^ ]*\/)?gh$/ && $2 == "api" && $3 == "graphql"')"
}

# a pull request opened on a branch names every example its change touches (examples-named.sh); the
# head is read from the write, `head=<branch>` or the JSON's head, and resolved in this checkout
examples() {
	local post body file head base files findings project
	project=${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)}
	while IFS= read -r post; do
		[ -n "$post" ] || continue
		body=$(gh_body "$post")
		case $body in ""|inline) continue ;; esac
		file=${body#* }
		[ -f "$file" ] || continue
		if [ "${body%% *}" = input ]; then
			head=$(jq -r '.head // empty' "$file" 2> /dev/null)
			jq -r '.body // empty' "$file" > "$tmp/examples-body" 2> /dev/null
			file=$tmp/examples-body
		else
			head=$(printf '%s' "$post" | grep -oE -- "(-f|-F|--raw-field|--field)[ =]head=[\"']?[^[:space:]\"']+" | head -n 1 | sed "s/.*head=[\"']\{0,1\}//")
		fi
		[ -n "$head" ] || continue
		if ! base=$(git -C "$project" merge-base origin/master "$head" 2> /dev/null); then
			echo "pr-body-guard: the head $head is not a ref this checkout can read, so the examples its change touches cannot be listed; fetch it, or pass EXAMPLES_OK=1 once the body says of each what it did." >&2
			exit 2
		fi
		files=$(git -C "$project" diff --name-only "$base" "$head")
		findings=$(cd "$project" && bash "$(dirname "$0")/examples-named.sh" "$file" $files) && continue
		echo "pr-body-guard: ${findings//$tmp\/examples-body/the body}" >&2
		echo "pr-body-guard: say of each what it did, ran, only loaded or not run and why, or pass EXAMPLES_OK=1 once the body does." >&2
		exit 2
	done <<< "$1"
}

# a new issue carries its severity as the repository's label (AGENTS.md, "Findings"): passed as a field of gh
# api, labels[]=, as gh issue's --label or -l, or in the JSON gh api sends
severity() {
	local post body
	while IFS= read -r post; do
		[ -n "$post" ] || continue
		body=$(gh_body "$post")
		if [ "${body%% *}" = input ]; then
			jq -e '[.labels[]? | strings | select(test("^severity: (low|medium|high)$"))] | length > 0' "${body#* }" \
				> /dev/null 2>&1 && continue
		elif printf '%s' "$post" | grep -qE '(labels\[\]=|--label[ =]|(^| )-l )([^ ,]*,)*severity: (low|medium|high)( |,|$)'; then
			continue
		fi
		echo "pr-body-guard: a new issue carries its severity as a label, severity: low, medium or high (AGENTS.md, \"Findings\"): pass -f 'labels[]=severity: <level>' to gh api, or --label to gh issue." >&2
		exit 2
	done <<< "$1"
}

cmds=$(commands "$input")
repo='^(https://api\.github\.com)?/?repos/[^/]+/[^/]+'
# a review or a comment is review-post-guard's, on an endpoint below the pull request's or the issue's
check "$(gh_writes "$cmds" 'pr (create|new|edit)' "$repo/pulls(/[0-9]+)?\$")" pr-body.sh
case "$(command_text "$input")" in
	*EXAMPLES_OK=1*) ;;
	*) examples "$(gh_writes "$cmds" 'pr (create|new)' "$repo/pulls\$")" ;;
esac
check "$(gh_writes "$cmds" 'issue (create|new|edit)' "$repo/issues(/[0-9]+)?\$")" untraced.sh added
# a new issue is a finding, read for a stimulus out of contract; an edit or a comment may argue about one
case "$(command_text "$input")" in
	*CONTRACT_OK=1*) ;;
	*) check "$(gh_writes "$cmds" 'issue (create|new)' "$repo/issues\$")" contract.sh ;;
esac
severity "$(gh_writes "$cmds" 'issue (create|new)' "$repo/issues\$")"
unread "$cmds"
exit 0

