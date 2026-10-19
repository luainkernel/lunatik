#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# doc/capi.md is written by hand, so a name a header of lib/ declares reaches it only if someone
# remembers to write its entry. For each lib/lua<name>.h given, this names every identifier of the
# header's own prefix, lua<name>_ or LUA<NAME>_, its comments and its include guard left out, that
# no C block of doc/capi.md carries: an entry spells its names there, where a heading escapes them.
# It catches a name missing, not an entry that no longer says what the code does.
#
# Usage: bash tools/checks/capi-entries.sh lib/*.h

root=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
doc=$root/doc/capi.md
status=0

entries=$(awk '/^```C$/ { c = 1; next } /^```/ { c = 0 } c' "$doc" 2>/dev/null)

for file in "$@"; do
	case "$file" in lib/lua*.h|*/lib/lua*.h) ;; *) continue ;; esac
	[ -f "$file" ] || continue
	stem=$(basename "$file" .h)
	guard=$(awk '$1 == "#ifndef" { print $2; exit }' "$file")
	names=$(gcc -fpreprocessed -dD -E -P -x c "$file" 2> /dev/null | grep -oE "\\b($stem|${stem^^})_[A-Za-z0-9_]*[A-Za-z0-9]" | sort -u)
	for name in $names; do
		[ "$name" = "$guard" ] && continue
		grep -qw -- "$name" <<< "$entries" && continue
		echo "$file: $name has no entry in doc/capi.md: a heading, its signature in a C block and what it raises, the context it runs in and who owns what it takes and returns"
		status=1
	done
done

exit $status

