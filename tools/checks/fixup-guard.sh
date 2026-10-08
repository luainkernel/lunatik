#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a pull request reaches the maintainer's first review squashed, so it does
# not open with a fixup!, amend! or squash! commit on its head. This blocks (exit 2) a gh write that
# creates a pull request whose head, compared on GitHub with its base, carries one, unless the
# command carries FIXUPS_OK=1; silent (exit 0) on everything else, and on a gh pr create that names
# no head, whose branch is the checkout's. Reads the command field of the raw hook input through
# commands.sh, as stacked-guard.sh does.

input=$(cat)

case "$input" in
	*"gh api"*pulls*head*|*"gh pr "*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

# the marker counts in the command, not in its description
case "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" in
	*FIXUPS_OK=1*) exit 0 ;;
esac

cmds=$(commands "$input")
creates=$(gh_writes "$cmds" 'pr (create|new)' '^(https://api\.github\.com)?/?repos/[^/]+/[^/]+/pulls$')
[ -n "$creates" ] || exit 0

quote="[\"'\\\\]*"
field="(-f|-F|--field|--raw-field)[ =]?"

# the value of a gh pr flag or of a gh api field in the write <write>
value() {
	if [ "$(printf '%s' "$1" | awk '{ print $2 }')" = pr ]; then
		printf '%s' "$1" | grep -oE "($2)${quote}[^[:space:]\"'\\\\]+" | sed -E "s/^($2)${quote}//"
	else
		printf '%s' "$1" | grep -oE "${field}${quote}$3=${quote}[^[:space:]\"'\\\\]+" | sed -E "s/^${field}${quote}$3=${quote}//"
	fi
}

while IFS= read -r create; do
	head=$(value "$create" '--head[ =]|-H ' head)
	[ -n "$head" ] || continue
	base=$(value "$create" '--base[ =]|-B ' base)
	repo=$(printf '%s' "$create" | grep -oE 'repos/[^/[:space:]"]+/[^/[:space:]"]+/pulls' | cut -d/ -f2-3)
	[ -n "$repo" ] || repo=$(printf '%s' "$create" | grep -oE "(--repo[ =]|-R )${quote}[^[:space:]\"'\\\\]+" | sed -E "s/^(--repo[ =]|-R )${quote}//")
	subjects=$(GH_TOKEN=$(gh_token "$input") gh api "repos/${repo:-{owner\}/{repo\}}/compare/${base:-master}...${head#*:}" \
		--jq '.commits[].commit.message | split("\n")[0]' 2>/dev/null)
	folds=$(printf '%s\n' "$subjects" | grep -E '^(fixup|amend|squash)! ')
	[ -n "$folds" ] || continue
	{
		echo "fixup-guard: $head reaches the maintainer's first review squashed, and it carries:"
		printf '%s\n' "$folds" | sed 's/^/  /'
		echo "fold them first (git rebase -i --autosquash, then git push --force-with-lease), or set FIXUPS_OK=1 on a pull request that is not the first he reads"
	} >&2
	exit 2
done <<< "$creates"

exit 0

