#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a push publishes whatever HEAD is when it runs. A rebase, a
# merge, a cherry-pick, an am or a revert that stops on a conflict leaves HEAD on the
# base with the branch's commits still to apply, and a push chained after it in the same
# command publishes that base as the branch. This blocks (exit 2) a git push in a command
# that also runs one of those, and a git push from a tree with one in progress, the
# session's cwd, any directory the command changes into or the one git -C gives the push,
# the latter unless the command carries the PUSH_OK=1 marker, set once git status was read
# and the push is meant. It also blocks a --force-with-lease=<ref>:<hash> whose full hash does not
# name a commit the push's tree holds: git sends it, and the remote refuses it as stale info,
# "failed to push some refs", with no word of the lease. Silent (exit 0) on everything else.
# Reads the command field of the raw hook input, which embeds it verbatim; the description
# beside it is not a command.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*push*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

cmds=$(commands "$input")
git=$GIT_COMMAND
printf '%s\n' "$cmds" | grep -Eq "$git push( |\$)" || exit 0

if printf '%s\n' "$cmds" | grep -Eq "$git (rebase|merge|cherry-pick|am|revert)( |\$)"; then
	echo "push-guard: the command runs a rebase, merge, cherry-pick, am or revert and a push; one that stops on a conflict leaves HEAD on the base, and the push publishes that as the branch. Read git status, then push as a command of its own." >&2
	exit 2
fi

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
while IFS=$'\t' read -r tree words; do
	git -C "$tree" rev-parse --git-dir > /dev/null 2>&1 || continue
	# shellcheck disable=SC2086 # the words of the push, as commands.sh split them
	for word in $words; do
		# a ref or an abbreviated hash git resolves before it sends, and refuses there when it cannot
		[[ $word =~ ^--force-with-lease=(refs/heads/)?([^:]*):([0-9a-f]{40})$ ]] || continue
		branch=${BASH_REMATCH[2]} sha=${BASH_REMATCH[3]}
		git -C "$tree" rev-parse --verify --quiet "$sha^{commit}" > /dev/null && continue
		echo "push-guard: the lease expects $sha, a commit $tree does not hold, and the remote refuses it as stale info; take the value from the checkout: --force-with-lease=$branch:\$(git rev-parse origin/$branch)" >&2
		exit 2
	done
done < <(git_pushes "$cmds" "$cwd")

case "$(command_text "$input")" in
	*PUSH_OK=1*) exit 0 ;;
esac

# each directory resolved against the one the command is in when it gets there
trees=$(printf '%s\n' "$cmds" | awk -v dir="$cwd" -v push="$git push( |\$)" '
	function under(base, path) {
		return path ~ /^\// ? path : base "/" path
	}
	BEGIN {
		print dir
	}
	$1 == "cd" && NF > 1 {
		print dir = under(dir, $2)
	}
	$0 ~ push {
		d = dir
		for (i = 2; $i != "push"; i++)
			if ($i == "-C")
				d = under(d, $++i)
		print d
	}')
while read -r tree; do
	[ -d "$tree" ] || continue
	gitdir=$(git -C "$tree" rev-parse --absolute-git-dir 2>/dev/null) || continue
	for state in rebase-merge:rebase rebase-apply:rebase MERGE_HEAD:merge CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert; do
		[ -e "$gitdir/${state%:*}" ] || continue
		echo "push-guard: $tree has a ${state#*:} in progress; finish or abort it, read git status, then push." >&2
		exit 2
	done
done <<< "$trees"
exit 0

