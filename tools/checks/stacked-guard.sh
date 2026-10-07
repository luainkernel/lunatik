#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a pull request opened on a base other than master opens as a draft, and
# one moved onto such a base is a draft already. GitHub does not merge a draft, and a stacked pull
# request merged before its base goes into the base's branch and not into master. This blocks
# (exit 2) a gh write that creates a pull request on another base without asking for a draft, or
# moves one there that GitHub, asked with the credential the command carries, does not answer is a
# draft; silent (exit 0) on everything else. Reads the command field of the raw hook input through
# commands.sh, as pr-body-guard.sh does.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*"gh api"*pulls*base*|*"gh pr "*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

cmds=$(commands "$input")
creates=$(gh_writes "$cmds" 'pr (create|new)' '^(https://api\.github\.com)?/?repos/[^/]+/[^/]+/pulls$')
moves=$(gh_writes "$cmds" 'pr edit' '^(https://api\.github\.com)?/?repos/[^/]+/[^/]+/pulls/[0-9]+$')
[ -n "$creates$moves" ] || exit 0

quote="[\"'\\\\]*"
field="(-f|-F|--field|--raw-field)[ =]?"

# the base the gh write <write> names: --base or -B on gh pr, a base= field on gh api, never the
# text of a --jq expression
base() {
	if [ "$(printf '%s' "$1" | awk '{ print $2 }')" = pr ]; then
		printf '%s' "$1" | grep -oE "(--base[ =]|-B )$quote[^[:space:]\"'\\\\]+" | sed -E "s/^(--base[ =]|-B )$quote//"
	else
		printf '%s' "$1" | grep -oE "${field}${quote}base=$quote[^[:space:]\"'\\\\]+" | sed -E "s/^${field}${quote}base=$quote//"
	fi
}

while IFS= read -r move; do
	base=$(base "$move")
	[ -z "$base" ] || [ "$base" = master ] && continue
	case "$(printf '%s' "$move" | awk '{ print $2 }')" in
	pr)
		repo=$(printf '%s' "$move" | grep -oE "(--repo[ =]|-R )$quote[^[:space:]\"'\\\\]+" | sed -E "s/^(--repo[ =]|-R )$quote//")
		number=$(printf '%s' "$move" | awk '{ for (i = 3; i <= NF; i++) if ($i ~ /^(#|.*\/pull\/)?[0-9]+$/) { sub(/.*[#\/]/, "", $i); print $i; exit } }')
		;;
	*)
		repo=$(printf '%s' "$move" | grep -oE 'repos/[^/[:space:]"]+/[^/[:space:]"]+/pulls/[0-9]+' | cut -d/ -f2-3)
		number=$(printf '%s' "$move" | grep -oE 'pulls/[0-9]+' | cut -d/ -f2)
		;;
	esac
	[ -n "$number" ] && [ "$(GH_TOKEN=$(gh_token "$input") gh api "repos/${repo:-{owner\}/{repo\}}/pulls/$number" --jq .draft 2>/dev/null)" = true ] && continue
	echo "stacked-guard: a pull request moved onto $base, not master, is a draft first (gh pr ready --undo <number>): GitHub will not merge a draft before its base, and the merged skill marks it ready when it retargets it." >&2
	exit 2
done <<< "$moves"

while IFS= read -r create; do
	base=$(base "$create")
	case "$(printf '%s' "$create" | awk '{ print $2 }')" in
	pr)
		draft=$(printf '%s' "$create" | grep -E "(^| )(--draft|-d)( |$)")
		;;
	*)
		draft=$(printf '%s' "$create" | grep -E "${field}${quote}draft=${quote}true")
		;;
	esac
	[ -z "$base" ] || [ "$base" = master ] || [ -n "$draft" ] && continue
	echo "stacked-guard: a pull request on $base, not master, opens as a draft (-F draft=true, or --draft): GitHub will not merge a draft before its base, and the merged skill marks it ready when it retargets it." >&2
	exit 2
done <<< "$creates"

exit 0

