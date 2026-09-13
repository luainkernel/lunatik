#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A change that adds a field to keep its own copy of a value another field
# carries has decided that the two can differ; every reader of the other field
# then has to decide which of the two it wants, and a review that proves why the
# copy exists tends to stop there. On #795 the copy was justified to the kernel
# line and the handler four lines above kept reading the original.
#
# For each C file given, every struct field the change adds whose trailing
# comment names another field (`kp.addr`, `hook->nfops`) is paired with the
# readers of that field in the file, and the readers are listed for the author
# to decide. A nudge: it prints the readers, it does not judge them.
#
# The base is HEAD, the pull request's base once its diff is staged, as the
# Checks workflow and pre-commit do; on a committed branch pass the base:
#
#     CHECK_BASE=origin/master bash tools/checks/shadowed-readers.sh lib/luaprobe.c
#
# Usage: bash tools/checks/shadowed-readers.sh <file>...

base=${CHECK_BASE:-HEAD}
status=0

for file in "$@"; do
	case "$file" in *.mod.c) continue ;; *.c|*.h) ;; *) continue ;; esac
	[ -f "$file" ] || continue
	found=$(git diff -U0 "$base" -- "$file" 2>/dev/null \
	| grep -E '^\+[[:space:]]+[A-Za-z_][A-Za-z0-9_ *]*[[:space:]*]+([A-Za-z_][A-Za-z0-9_]*)(\[[^]]*\])?;[[:space:]]*/\*.*[A-Za-z_][A-Za-z0-9_]*(\.|->)[A-Za-z_][A-Za-z0-9_]*.*\*/' \
	| while IFS= read -r added; do
		field=$(sed -E 's/^\+[[:space:]]+.*[[:space:]*]+([A-Za-z_][A-Za-z0-9_]*)(\[[^]]*\])?;.*/\1/' <<< "$added")
		other=$(grep -oE '[A-Za-z_][A-Za-z0-9_]*(\.|->)[A-Za-z_][A-Za-z0-9_]*' <<< "${added#*/\*}" | head -1)
		member=${other##*[.>]}
		readers=$(grep -nE "(\.|->)$member\b" "$file" | grep -vE "^[0-9]+:[[:space:]]*(/\*|\*|//)" | grep -v "\b$field\b")
		[ -n "$readers" ] || continue
		echo "$file adds $field beside $other; these still read $member, and each has to say which of the two it wants:"
		printf '%s\n' "$readers" | sed 's/^/  /'
	done)
	[ -z "$found" ] || { printf '%s\n' "$found"; status=1; }
done

exit $status

