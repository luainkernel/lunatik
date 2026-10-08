#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names what lua-language-server reports at its warning level in the Lua files given, read with the
# tree's .luarc.json: a local or a function declared and never read, and a global assigned where a
# local was meant. Each directory is checked once, and
# only the files given are reported. Silent without a Lua file; says so when the server is absent.
#
# Usage: bash tools/checks/luals.sh <file>...

# each file is reported as it was given, which is how the edit hook matches a finding to its lines
given=()
files=()
for file in "$@"; do
	case "$file" in
		lua/*|*/lua/*|klibc/*|*/klibc/*|luac/*|*/luac/*) ;;
		*.lua) [ -f "$file" ] && given+=("$file") && files+=("$(realpath "$file")") ;;
	esac
done
[ ${#files[@]} -gt 0 ] || exit 0

if ! command -v lua-language-server > /dev/null; then
	echo "luals: not run, it needs lua-language-server"
	exit 0
fi

root=$(git -C "$(dirname "${files[0]}")" rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -f "$root/.luarc.json" ] || exit 0

# the server writes the definitions of the standard library under its metapath, which must be writable
meta=${XDG_CACHE_HOME:-$HOME/.cache}/lunatik/luals-meta
mkdir -p "$meta"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# the server reads comments in a workspace's own .luarc.json and not in the file --configpath names
grep -v '^[[:space:]]*//' "$root/.luarc.json" > "$tmp/luarc.json"

for dir in $(printf '%s\n' "${files[@]}" | xargs -n 1 dirname | sort -u); do
	out="$tmp/$(printf '%s' "$dir" | md5sum | cut -c1-8).json"
	lua-language-server --check "$dir" --configpath "$tmp/luarc.json" --checklevel=Warning \
		--metapath "$meta" --logpath "$tmp/log" --check_format=json --check_out_path "$out" > /dev/null 2>&1
done

for i in "${!files[@]}"; do
	cat "$tmp"/*.json 2> /dev/null | jq -rs --arg uri "file://${files[$i]}" --arg path "${given[$i]}" '
		[.[] | to_entries[] | select(.key == $uri) | .value[]] | unique_by(.range.start.line, .code)[] |
		"\($path):\(.range.start.line + 1): \(.code): \(.message | split("\n")[0])"'
done

