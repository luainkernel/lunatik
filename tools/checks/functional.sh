#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names the files a change touches in what the host cycle reads, the build, the install and the suite.
# A change to comments and spacing alone, or to a document, the harness, a .gitignore or the binding
# template, alters no module and no script, and the suite would measure what it measured already. A C
# file counts when its tokens differ once the comments are gone, a Lua file when the listing of its
# stripped bytecode does, read without the lines its functions span and the addresses it was loaded at,
# a shell script when a line other than a comment does, a submodule when the commit it points at does,
# and any other file when its bytes or its mode do; one the compiler cannot read counts too. Exits 1 when
# it names one.
#
# Usage: bash tools/checks/functional.sh <base> [<head>]   (default head HEAD)

set -o pipefail # a compiler that cannot read the file fails the pipe it feeds
base=$1
head=${2:-HEAD}
[ -n "$base" ] || { echo "usage: $0 <base> [<head>]" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# what the build reads of <path> at <rev>, as a checksum; nothing when the file is not there
code() {
	local rev=$1 path=$2

	# a submodule's commit is in its own objects, not here: the commit it points at stands for it
	git show "$rev:$path" > "$tmp/file" 2> /dev/null || { git rev-parse --verify -q "$rev:$path"; return 0; }
	git ls-tree "$rev" -- "$path" | cut -c1-6
	case "$path" in
		# -fpreprocessed joins no continuation, and reads a "#name" that opens one as a directive
		*.c|*.h) sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$tmp/file" | gcc -fpreprocessed -dD -E -P -x c - 2> /dev/null |
			tr -s ' \t\n' ' ' > "$tmp/code" ;;
		# a stripped chunk keeps the lines each function spans, which its listing's header carries
		*.lua) luac5.5 -s -o - "$tmp/file" 2> /dev/null | luac5.5 -p -l -l - | sed -E \
			-e 's/^(main|function) <[^>]*> \((.*) at 0x[0-9a-f]+\)$/\1 (\2)/' \
			-e 's/ for 0x[0-9a-f]+:$/:/' -e 's/(CLOSURE.*; )0x[0-9a-f]+$/\1/' > "$tmp/code" ;;
		*.sh) sed '1!{/^[[:space:]]*#/d;}' "$tmp/file" | tr -s ' \t\n' ' ' > "$tmp/code" ;;
		*) cp "$tmp/file" "$tmp/code" ;;
	esac || { echo "$rev: unreadable"; return; }
	cksum < "$tmp/code"
}

status=0
while read -r path; do
	case "$path" in
		*.md|config.ld|doc/*|.agents/*|.claude/*|.github/*|tools/checks/*|.gitignore|*/.gitignore) continue ;;
		# the binding template, which no Kbuild line builds
		lib/luaskel.c) continue ;;
	esac
	[ "$(code "$base" "$path")" = "$(code "$head" "$path")" ] && continue
	echo "$path"
	status=1
done < <(git diff --name-only "$base" "$head")
exit $status

