#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash) hook: a push does not publish a name lua-language-server reads as a slip on a
# line the branch added. luals.sh names it at edit time, and an edit that goes on regardless reaches
# the pull request; what the branch inherited from its base is not this push's to fix. This blocks
# (exit 2) a git push whose tree, read against its merge base with origin/master, adds such a line,
# unless the command carries LUALS_OK=1; silent (exit 0) on everything else, and where the tree
# carries no luals.sh. Reads the command field of the raw hook input through commands.sh.

input=$(cat)

case "$input" in
	*"git "*push*) ;;
	*) exit 0 ;;
esac

. "$(dirname "$0")/commands.sh"

cmds=$(commands "$input")
printf '%s\n' "$cmds" | grep -Eq "$GIT_COMMAND push( |\$)" || exit 0
case "$(command_text "$input")" in
	*LUALS_OK=1*) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
tree=$(git_pushes "$cmds" "$cwd" | tail -n 1 | cut -f 1)
root=$(git -C "$tree" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/tools/checks/luals.sh" ] && [ -f "$root/.luarc.json" ] || exit 0
base=$(git -C "$root" merge-base HEAD origin/master 2>/dev/null) || exit 0
files=$(git -C "$root" diff --name-only --diff-filter=ACM "$base" HEAD -- '*.lua')
[ -n "$files" ] || exit 0

# shellcheck disable=SC2086 # one path per word, as git prints them
findings=$(cd "$root" && bash tools/checks/luals.sh $files)
added=$(printf '%s\n' "$findings" | while IFS=: read -r file line rest; do
	[ -n "$rest" ] || continue
	git -C "$root" diff -U0 "$base" HEAD -- "$file" | awk -v n="$line" '
		/^@@/ {
			split($3, h, /[+,]/)
			if (n >= h[2] && n < h[2] + (h[3] == "" ? 1 : h[3]))
				found = 1
		}
		END {
			exit !found
		}' && printf '%s:%s:%s\n' "$file" "$line" "$rest"
done)
[ -n "$added" ] || exit 0

{
	echo "luals-guard: the push adds what lua-language-server reads as a slip:"
	printf '%s\n' "$added" | sed 's/^/  /'
	echo "fix it in the commit that added it, or set LUALS_OK=1 where the name is the code's on purpose"
} >&2
exit 2

