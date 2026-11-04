#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a pull request that changes a binding is not opened
# before the out-of-tree scripts that load it were read. Reads the tool command
# on stdin, runs consumers.sh over the change of each pull request a gh write
# opens or edits, from its base to its head, as pr-body-guard
# reads them, and blocks (exit 2) when a consumer turns up, or when the checkout
# cannot read that change, unless the command carries CONSUMERS_OK=1, set once
# they were read. Silent when LUNATIK_CONSUMERS is unset or nothing matches.

input=$(cat)

# a cheap bail on the raw input, which carries the description too; the command itself decides below
case "$input" in
	*"gh api"*pulls*|*"gh pr "*) ;;
	*) exit 0 ;;
esac
[ -n "$LUNATIK_CONSUMERS" ] || exit 0

. "$(dirname "$0")/commands.sh"

case "$(command_text "$input")" in
	*CONSUMERS_OK=1*) exit 0 ;;
esac

project=${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)}
cmds=$(commands "$input")
while IFS= read -r post; do
	[ -n "$post" ] && gh_ours "$post" || continue
	read -r base head <<< "$(gh_refs "$input" "$post")"
	if ! files=$(gh_change "$input" "$post" "$base" "$head" "$project"); then
		echo "consumers-guard: the change from $base to ${head:-a head neither the write nor GitHub names} is not one this checkout can read, so the bindings it touches cannot be listed; fetch the ref, or pass CONSUMERS_OK=1 once the consumers were read." >&2
		exit 2
	fi
	report=$(cd "$project" && bash "$(dirname "$0")/consumers.sh" $files)
	[ -n "$report" ] || continue
	echo "$report" >&2
	echo "consumers-guard: read them, then re-run with CONSUMERS_OK=1 as a command prefix." >&2
	exit 2
done <<< "$(gh_writes "$cmds" 'pr (create|new|edit)' '^(https://api\.github\.com)?/?repos/[^/]+/[^/]+/pulls(/[0-9]+)?$')"
exit 0

