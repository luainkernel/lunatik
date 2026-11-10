#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: an install, reload or run over a tree that drops a crash
# guard reproduces the crash the guard prevents, and on the shared host that is a
# forced reboot. This blocks (exit 2) make install, lunatik reload/run/spawn/test and
# a direct test run while a tree it reads, against its HEAD, removes a line carrying a
# guard, unless the command carries the CRASH_AB_OK=1 marker, set by
# hand once the maintainer authorized the experiment and named the machine it may
# take down. Silent (exit 0) on everything else. The marker forces the ask; it cannot
# check that the answer was yes, only that it was set on purpose.
# The worktrees are read before the command runs, so a command line that also writes a C
# source or header, the target of a redirection, a file a sed -i names or a path a git
# checkout or a git restore names, a directory among them, is blocked with the same marker:
# the edit goes in a call of its own, and the install after it is read against the tree the
# edit left. A write a script file makes is not on the line, which is all this reads, and one
# spelled another way, a cp or a tee, is not read.
# A line that installs reads the tree each make install runs in, which is what the runs
# after it on the line run; a line that only runs what is installed, one that runs before
# its first install, one whose tree is not resolved and one that moves a directory by a
# spelling other than cd and make's -C or --directory read every worktree of the project,
# since the install under /lib/modules/lua may be any of theirs.
# What the command runs is read by commands.sh, from the raw hook input.

input=$(cat)

. "$(dirname "$0")/commands.sh"

# whether <cmds> runs what is installed: a reload, run or test
runs() {
	runs_lunatik "$1" '(reload|run|spawn|test)( |$)' || runs_test "$1" || runs_watchdog "$1"
}

# whether the command <text> moves a directory where install_dirs does not follow it: pushd, env -C,
# sudo -D, and a make option for a directory other than -C and --directory, a prefix or a cluster
moves() {
	printf '%s\n' "$1" | grep -Eq '(^|[^[:alnum:]_-])(pushd|popd)( |$)|--chdir|(^|[ ;&|(])env( [^ ;&|]+)* -C|(^|[ ;&|(])sudo( [^ ;&|]+)* -D|(^| )--d(i|ir|ire|irec|irect|irecto|irector)?(=| |$)|(^| )-[a-zA-Z]+C'
}

# whether <cmds> runs what is installed before its first make install, or installs nothing
runs_first() {
	local cmd
	while IFS= read -r cmd; do
		runs_install "$cmd" && return 1
		runs "$cmd" && return 0
	done <<< "$1"
	return 0
}

cmds=$(commands "$input")
runs "$cmds" || runs_install "$cmds" || exit 0

case "$(command_text "$input")" in
	*CRASH_AB_OK=1*) exit 0 ;;
esac

# the C sources and headers the command line writes: the targets of its redirections, the words of a
# sed -i, and the paths past a git checkout or a git restore, a directory among them by its slash or as .
written=$({
	redirections "$input"
	printf '%s\n' "$cmds" | grep -E '^([^ ]*/)?sed( .*)? (-[A-Za-z]*i[^ ]*|--in-place[^ ]*)( |$)' | tr ' ' '\n'
} | grep -E '\.[ch]$'
printf '%s\n' "$cmds" | sed -En "s@$GIT_COMMAND (checkout|restore) @@p" | tr ' ' '\n' | grep -E '\.[ch]$|/$|^\.$')
if [ -n "$written" ]; then
	echo "crash-guard: the command writes $(paste -sd' ' <<< "$written") and installs or runs in one call; the worktrees are read before the call runs, so a guard the write drops is installed unseen. Make the edit in a call of its own, then install or run." >&2
	exit 2
fi

. "$(dirname "$0")/guards.sh"

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
trees=
if [ -n "$cwd" ] && ! runs_first "$cmds" && ! moves "$(command_text "$input")"; then
	trees=$(install_dirs "$cmds" "$cwd" | while read -r dir; do
		git -C "$dir" rev-parse --show-toplevel 2>/dev/null || exit 1
	done) || trees=
fi
if [ -z "$trees" ]; then
	project=${CLAUDE_PROJECT_DIR:-$cwd}
	[ -d "$project" ] || exit 0
	trees=$(git -C "$project" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
fi

removed=$(printf '%s\n' "$trees" | while read -r tree; do
	[ -d "$tree" ] || continue
	dropped_guards "$tree" '*.c' '*.h' | sed "s|^|$tree: |"
done)
[ -z "$removed" ] && exit 0

echo "crash-guard: a worktree drops a crash guard; installing or running it reproduces the crash the guard prevents, which on the shared host is a forced reboot:" >&2
echo "$removed" >&2
echo "crash-guard: commit the change if it is not an experiment; for an experiment, get the maintainer's authorization and the machine it may take down, then re-run with CRASH_AB_OK=1 as a command prefix." >&2
exit 2

