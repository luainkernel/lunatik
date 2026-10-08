#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a push publishes the commit messages and the branch name along with the
# tree, and machine-leak.sh, which the commit gate runs over the files, reads neither. This blocks
# (exit 2) a git push whose commits past origin/master carry in their messages, or whose refspec
# carries in its names, what machine-leak.sh reads as the machine or a private repository; silent
# (exit 0) on everything else. A leak takes no marker: what is pushed is read by everyone who
# clones. Reads the command field of the raw hook input through commands.sh, as push-guard.sh does.

input=$(cat)

case "$input" in
	*push*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

cmds=$(commands "$input")
printf '%s\n' "$cmds" | grep -Eq "$GIT_COMMAND push( |\$)" || exit 0

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git_pushes "$cmds" "$cwd" > "$tmp/pushes"

scan=$tmp/scan
mkdir "$scan"
found=""
while IFS=$'\t' read -r tree words; do
	root=$(git -C "$tree" rev-parse --show-toplevel 2>/dev/null) || continue
	rm -f "$scan"/*
	# the refspec is the last word that is not an option; its source is what the push publishes
	spec=$(printf '%s\n' $words | grep -v '^-' | tail -n 1)
	src=${spec%%:*}
	src=${src#+}
	git -C "$root" rev-parse --verify --quiet "${src:-HEAD}^{commit}" > /dev/null || src=HEAD
	# a branch name joins its words with _, - and /, which the rules read as part of a word
	printf '%s\n' "$spec" | tr ':_/-' '\n' > "$scan/refspec"
	for commit in $(git -C "$root" rev-list "origin/master..${src:-HEAD}" 2>/dev/null); do
		git -C "$root" log -1 --format=%B "$commit" > "$scan/$commit"
	done
	found=$found$(cd "$root" && bash tools/checks/machine-leak.sh "$scan"/* 2>/dev/null |
		sed "s|^$scan/refspec|the refspec|; s|^$scan/\([0-9a-f]\{9\}\)[0-9a-f]*|commit \1|")
done < "$tmp/pushes"
[ -n "$found" ] || exit 0

{
	echo "leak-guard: the push publishes what belongs to the machine or a private repository:"
	printf '%s\n' "$found" | sed 's/^/  /'
	echo "reword the message (git rebase -i, reword) or rename the branch, then push"
} >&2
exit 2

