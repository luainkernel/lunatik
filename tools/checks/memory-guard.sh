#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# PreToolUse (Bash, Write and Edit) hook: a lesson kept in one assistant's notes is one the next
# contributor pays for again, and a session wrote one into its Claude Code memory, a file under
# .claude/projects/<project>/memory/, and not into the tree. This blocks (exit 2) a call that leaves
# there a memory of type feedback when what the call adds names no path of the repository where the
# lesson lives, AGENTS.md or a path under .agents/, tools/ or doc/; silent (exit 0) on the other
# types, the index MEMORY.md, which has none, among them, and on every other file. What a call adds
# is what Write writes, the new_string of an Edit and the whole command of a shell write, a
# redirection, a tee or a sed -i into a memory read through commands.sh, its path spelled whole,
# through a variable the command assigns or under a directory it changes to; the type is read in the
# memory as the call leaves it, for a shell write the file as it stands with the command beside it.

input=$(cat)

case "$input" in
	*/memory*) ;;
	*) exit 0 ;;
esac

MEMORY='(^|/)\.claude/projects/[^/]+/memory/[^/]+\.md$'

# the path <path> as the shell reads it, ~ or a variable at its head expanded: $HOME to this shell's,
# another to the value the command assigns it
expand() {
	local path=$1
	if [[ $path =~ ^\$\{?([A-Za-z_][A-Za-z_0-9]*)\}?(/.*)?$ ]] && [ "${BASH_REMATCH[1]}" != HOME ]; then
		path=$(grep -oE "(^|[^A-Za-z_0-9])${BASH_REMATCH[1]}=[^[:space:];&|)]+" <<< "$command" | head -n 1 |
			sed -E "s/^[^=]*=//; s/[\"']//g")${BASH_REMATCH[2]}
	fi
	case "$path" in
		"~/"*) printf '%s/%s' "$HOME" "${path#\~/}" ;;
		'$HOME/'*|'${HOME}/'*) printf '%s/%s' "$HOME" "${path#*/}" ;;
		*) printf '%s' "$path" ;;
	esac
}

# where a write to each path of stdin lands, one a line: the path as the shell reads it and, for a
# relative one, the path under each directory of <dirs>, those the command changes to
landings() {
	local target dir
	while IFS= read -r target; do
		target=$(expand "$target")
		printf '%s\n' "$target"
		[[ $target == /* ]] || while IFS= read -r dir; do
			[ -z "$dir" ] || printf '%s/%s\n' "$(expand "${dir%/}")" "$target"
		done <<< "$1"
	done
}

# whether the memory <text> is a lesson and <added>, what the call writes into it, names no path of
# the repository
unplaced() {
	grep -Eq '^[[:space:]]*type:[[:space:]]*feedback[[:space:]]*$' <<< "$1" &&
		! grep -Eq 'AGENTS\.md|\.agents/|tools/|doc/' <<< "$2"
}

found=
case "$(printf '%s' "$input" | jq -r '.tool_name')" in
	Write|Edit)
		target=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
		[[ $target =~ $MEMORY ]] || exit 0
		file=$target
		[ -f "$file" ] || file=/dev/null
		# an empty old_string creates the file; another is unique unless replace_all is set, so each is replaced
		text=$(printf '%s' "$input" | jq -r --rawfile file "$file" '.tool_input as $t | $t.content //
			if $t.old_string == "" then $t.new_string else $file | split($t.old_string) | join($t.new_string) end')
		added=$(printf '%s' "$input" | jq -r '.tool_input | .content // .new_string')
		unplaced "$text" "$added" && found=" ${target##*/}"
		;;
	Bash)
		. "$(dirname "$0")/commands.sh"
		command=$(command_text "$input")
		while IFS= read -r target; do
			[ -n "$target" ] || continue
			file=$target
			[ -f "$file" ] || file=/dev/null
			unplaced "$(cat "$file")"$'\n'"$command" "$command" && found="$found ${target##*/}"
		done <<< "$({
			redirections "$input"
			commands "$input" | awk '
			{
				k = $1
				sub(/.*\//, "", k)
				edit = k == "tee"
				for (i = 2; k == "sed" && i <= NF; i++)
					edit = edit || $i ~ /^(-[^-]*i|--in-place)/
				for (i = 2; edit && i <= NF; i++)
					print $i
			}'
		} | landings "$(commands "$input" | awk '$1 == "cd" { print $2 }')" | grep -E "$MEMORY" | sort -u)"
		;;
esac
[ -n "$found" ] || exit 0

{
	echo "memory-guard:$found: a write to a lesson, a memory of type feedback, whose own text names"
	echo "no path of the repository where the lesson lives; a #N is not one. Put the lesson in the tree first,"
	echo "through a pull request, in AGENTS.md, a rule or a skill under .agents/, a check under tools/ or a page"
	echo "under doc/, and name that path in what this write adds. A lesson that belongs to no place of the public"
	echo "tree, the language of the conversation, the tone, a private consumer, is a memory of type user, which"
	echo "this guard does not read; an Edit of the type line, not a sed -i, makes an existing memory one."
} >&2
exit 2

