#!/usr/bin/env bash
# PreToolUse (Bash) hook: a pull request body is posted only when pr-body.sh passes on
# it, and an issue body only when untraced.sh does, since the paragraphs and the Closes
# line are a pull request's. This blocks (exit 2) a gh write to pulls or issues that
# carries a body file (-F body=@file) the check fails on, printing the findings; silent
# (exit 0) on everything else.
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
	*"gh api"*pulls*body=*|*"gh pr create"*--body*|*"gh pr edit"*--body*) ;;
	*"gh api"*issues*body=*|*"gh issue create"*--body*|*"gh issue edit"*--body*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

flag="(body=@|--body-file[ =])"

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
	local post file scan leaked findings
	while IFS= read -r post; do
		[ -n "$post" ] || continue
		# the quotes gh is written with are not part of the path: skipped before it, excluded from it
		file=$(printf '%s' "$post" | grep -oE "$flag[\"'\\\\]*[^[:space:]\"'\\\\]+" | sed -E "s/^$flag[\"'\\\\]*//" | head -1)
		if [ -z "$file" ]; then
			echo "pr-body-guard: a body is read from a file: pass it as --body-file <file>." >&2
			exit 2
		fi
		if [ ! -f "$file" ]; then
			echo "pr-body-guard: a body is read from a file, and $file is not one. A path written as a shell variable arrives here unexpanded: spell it out." >&2
			exit 2
		fi

		scan=$file
		[ -z "$3" ] || { scan=$(mktemp); added "$post" "$file" > "$scan"; }
		leaked=$(bash "$(dirname "$0")/machine-leak.sh" "$scan")
		findings=$(bash "$(dirname "$0")/$2" "$scan")
		[ "$scan" = "$file" ] || { rm -f "$scan"; leaked=${leaked//$scan/$file}; findings=${findings//$scan/$file}; }
		if [ -n "$leaked" ]; then
			echo "pr-body-guard: the body carries what belongs to the machine it was written on:" >&2
			echo "$leaked" >&2
			echo "pr-body-guard: rewrite the line and re-run." >&2
			exit 2
		fi

		[ -z "$findings" ] && continue

		echo "pr-body-guard: $findings" >&2
		exit 2
	done <<< "$(printf '%s\n' "$1" | grep -E ' (--body(-file)?([ =]|$)|body=)')"
}

cmds=$(commands "$input")
repo='^(https://api\.github\.com)?/?repos/[^/]+/[^/]+'
# a review or a comment is review-post-guard's, on an endpoint below the pull request's or the issue's
check "$(gh_writes "$cmds" 'pr (create|edit)' "$repo/pulls(/[0-9]+)?\$")" pr-body.sh
check "$(gh_writes "$cmds" 'issue (create|edit)' "$repo/issues(/[0-9]+)?\$")" untraced.sh added
exit 0

