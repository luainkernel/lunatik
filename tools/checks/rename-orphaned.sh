#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A type renamed to tell it apart from a sibling keeps that name after the sibling
# is gone, because the squash pass re-reads comments and commit bodies and not
# identifiers. This reads the identifiers: for each C file given, the typedefs the
# change removes and adds are paired as a rename, and a rename that adds a noun in
# a file the change leaves with one typedef is reported, since the noun then tells
# the type apart from nothing.
#
# The base is HEAD, which is the pull request's base once its diff is staged, as
# the Checks workflow and pre-commit do; on a committed branch pass the base:
#
#     CHECK_BASE=origin/master bash tools/checks/rename-orphaned.sh lib/luaprobe.c
#
# Usage: bash tools/checks/rename-orphaned.sh <file>...

base=${CHECK_BASE:-HEAD}
status=0

typedefs() { grep -oE '^} (lua[a-z0-9]+|lunatik)_[a-z0-9_]*t;' | sed 's/^} //; s/;$//'; }

for file in "$@"; do
	case "$file" in *.c|*.h) ;; *) continue ;; esac
	[ -f "$file" ] || continue
	before=$(git show "$base:$file" 2>/dev/null | typedefs)
	after=$(typedefs < "$file")
	removed=$(comm -23 <(echo "$before" | sort) <(echo "$after" | sort))
	added=$(comm -13 <(echo "$before" | sort) <(echo "$after" | sort))
	[ -n "$removed" ] && [ -n "$added" ] || continue
	[ "$(echo "$after" | grep -c .)" -eq 1 ] || continue
	for new in $added; do
		for old in $removed; do
			# a noun was added: the new name has more segments than the old one
			[ "$(tr -cd _ <<< "$new" | wc -c)" -gt "$(tr -cd _ <<< "$old" | wc -c)" ] || continue
			echo "$file renames $old to $new, adding a noun, and $new is the only typedef left:"
			echo "  the noun told it apart from a type this change removed; on the final shape it tells"
			echo "  it apart from nothing. Read the identifiers after a squash as the comments are read"
			status=1
		done
	done
done

exit $status

