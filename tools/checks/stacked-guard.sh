#!/usr/bin/env bash
# PreToolUse (Bash) hook: a pull request opened on a base other than master opens as a draft.
# GitHub does not merge a draft, and a stacked pull request merged before its base goes into
# the base's branch and not into master. This blocks (exit 2) a gh write that creates a pull
# request on another base without asking for a draft; silent (exit 0) on everything else.
# Reads the command field of the raw hook input through commands.sh, as pr-body-guard.sh does.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*"gh api"*pulls*base*|*"gh pr create"*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

creates=$(gh_writes "$(commands "$input")" 'pr create' '^(https://api\.github\.com)?/?repos/[^/]+/[^/]+/pulls$')
[ -n "$creates" ] || exit 0

quote="[\"'\\\\]*"
while IFS= read -r create; do
	case "$(printf '%s' "$create" | awk '{ print $2 }')" in
	pr)
		base=$(printf '%s' "$create" | grep -oE "(--base[ =]|-B )$quote[^[:space:]\"'\\\\]+" | sed -E "s/^(--base[ =]|-B )$quote//")
		draft=$(printf '%s' "$create" | grep -E "(^| )(--draft|-d)( |$)")
		;;
	*)
		base=$(printf '%s' "$create" | grep -oE "(^|[ =])${quote}base=$quote[^[:space:]\"'\\\\]+" | sed -E "s/^[ =]?${quote}base=$quote//")
		draft=$(printf '%s' "$create" | grep -E "(^|[ =])${quote}draft=${quote}true")
		;;
	esac
	[ -z "$base" ] || [ "$base" = master ] || [ -n "$draft" ] && continue
	echo "stacked-guard: a pull request on $base, not master, opens as a draft (-F draft=true, or --draft): GitHub will not merge a draft before its base, and the merged skill marks it ready when it retargets it." >&2
	exit 2
done <<< "$creates"

exit 0

