#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a force-push rewrites history, and every branch started
# from the one being rewritten keeps the commits it drops. They surface later as a
# duplicate of a commit that no longer exists, in a pull request nobody edited.
# AGENTS.md covers a branch checked out elsewhere and the body a rewrite invalidates;
# this covers the branches based on it, which is what `git push --force` cannot see.
# Blocks (exit 2) a forced push, --force, --force-with-lease, -f or a refspec opening with +, of a
# branch other refs descend from, the refspec's destination where a local branch carries that name
# and its source otherwise. Reads the command field of the raw hook input through commands.sh, so
# a command that only mentions a push passes. REWRITE_OK=1 runs it once the list below is known to
# be stale.

input=$(cat)

case "$input" in
	*push*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

cmds=$(commands "$input")
printf '%s\n' "$cmds" | grep -Eq "$GIT_COMMAND push( |\$)" || exit 0
case "$(command_text "$input")" in
	*REWRITE_OK=1*) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
while IFS=$'\t' read -r tree words; do
	git -C "$tree" rev-parse --git-dir > /dev/null 2>&1 || continue
	# shellcheck disable=SC2086 # the words of the push, as commands.sh split them
	set -- $words
	forced=0
	refspecs=()
	for word; do
		case "$word" in
			--force|--force-with-lease|--force-with-lease=*|--force-if-includes|-f) forced=1 ;;
			-*) ;;
			+*) forced=1; refspecs+=("${word#+}") ;;
			*) refspecs+=("$word") ;;
		esac
	done
	[ $forced -eq 1 ] || continue
	# the first word that is not an option is the remote
	for spec in "${refspecs[@]:1}"; do
		dst=${spec#*:}
		dst=${dst#refs/heads/}
		branch=$dst
		git -C "$tree" rev-parse --verify --quiet "refs/heads/$branch" > /dev/null || branch=${spec%%:*}
		[ "$branch" = HEAD ] && branch=$(git -C "$tree" symbolic-ref -q --short HEAD)
		git -C "$tree" rev-parse --verify --quiet "$branch^{commit}" > /dev/null || continue
		based=$(git -C "$tree" branch --format='%(refname:short)' --contains "$branch" | grep -vx "$branch" | grep -vx "$dst")
		[ -n "$based" ] || continue
		{
			echo "rewrite-guard: these branches are based on '$branch' and keep what this push drops:"
			printf '  %s\n' $based
			echo "rewrite-guard: rebase them onto the rewritten branch, or re-run with REWRITE_OK=1 once that list is stale."
		} >&2
		exit 2
	done
done < <(git_pushes "$cmds" "$cwd")
exit 0

