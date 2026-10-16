#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a checkout or a restore of a path, a hard reset and a forced checkout or
# switch write over the work tree, and a change nobody committed goes with no copy left. Blocks
# (exit 2) such a command while a file it writes over holds one, naming the files: the work is
# committed first, and a defect planted to prove a test is reverted with `git apply -R` of its patch.
# Reads the command field of the raw hook input through commands.sh, so a command that only mentions
# a checkout passes. DISCARD_OK=1 runs it once the files it names hold nothing to keep.

input=$(cat)

case "$input" in
	*checkout*|*restore*|*reset*|*switch*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

cmds=$(commands "$input")
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
found=

# what the repository at <tree> holds uncommitted under the paths after it, or anywhere with none
check() {
	local tree=$1 file
	shift
	git -C "$tree" rev-parse --git-dir > /dev/null 2>&1 || return
	while read -r file; do
		[ -n "$file" ] && found="$found  $tree: $file"$'\n'
	done < <(git -C "$tree" status --porcelain --untracked-files=no -- "$@" | cut -c4-)
}

while IFS=$'\t' read -r tree words; do
	# shellcheck disable=SC2086 # the words of the checkout, as commands.sh split them
	set -- $words
	args=()
	forced=0
	while [ $# -gt 0 ]; do
		case "$1" in
			--) shift; break ;;
			-b|-B|--orphan) continue 2 ;; # a new branch carries the work tree
			-f|--force) forced=1 ;;
			-*) ;;
			*) args+=("$1") ;;
		esac
		shift
	done
	# the words past --, or past a first one that names a commit, are paths, and all of them when it names none
	if [ $# -gt 0 ]; then
		check "$tree" "$@"
	elif [ ${#args[@]} -gt 0 ] && ! git -C "$tree" rev-parse --verify --quiet "${args[0]}^{commit}" > /dev/null 2>&1; then
		check "$tree" "${args[@]}"
	elif [ ${#args[@]} -gt 1 ]; then
		check "$tree" "${args[@]:1}"
	elif [ $forced -eq 1 ]; then
		check "$tree"
	fi
done < <(git_runs "$cmds" "$cwd" checkout)

while IFS=$'\t' read -r tree words; do
	# shellcheck disable=SC2086 # the words of the restore, as commands.sh split them
	set -- $words
	paths=()
	staged=0
	worktree=0
	while [ $# -gt 0 ]; do
		case "$1" in
			--) shift; paths+=("$@"); break ;;
			-S|--staged) staged=1 ;;
			-W|--worktree) worktree=1 ;;
			-s|--source) shift ;;
			-*) ;;
			*) paths+=("$1") ;;
		esac
		shift
	done
	[ $staged -eq 1 ] && [ $worktree -eq 0 ] && continue # the index alone
	[ ${#paths[@]} -gt 0 ] && check "$tree" "${paths[@]}"
done < <(git_runs "$cmds" "$cwd" restore)

while IFS=$'\t' read -r tree words; do
	case " $words " in
		*" --hard "*) check "$tree" ;;
	esac
done < <(git_runs "$cmds" "$cwd" reset)

while IFS=$'\t' read -r tree words; do
	case " $words " in
		*" -f "*|*" --force "*|*" --discard-changes "*) check "$tree" ;;
	esac
done < <(git_runs "$cmds" "$cwd" switch)

[ -n "$found" ] || exit 0
case "$(command_text "$input")" in
	*DISCARD_OK=1*) exit 0 ;;
esac

{
	echo "discard-guard: this command writes over changes nobody committed:"
	printf '%s' "$found"
	echo "discard-guard: commit them first, and revert a planted defect with git apply -R of its patch; re-run with DISCARD_OK=1 as a command prefix only when what is listed holds nothing to keep."
} >&2
exit 2

