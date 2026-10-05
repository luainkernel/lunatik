#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names the out-of-tree scripts that require a binding the given files change.
# A product built on Lunatik is a consumer this tree cannot grep: point the check
# at the clones with LUNATIK_CONSUMERS, a colon separated list of directories,
# and it reports which of their scripts load what is being changed, or reach it
# through what tools/checks/modules.sh names. Silent when the variable is unset,
# when no file defines a module, or when no consumer script requires one.
#
# Usage: LUNATIK_CONSUMERS=/path/a:/path/b bash tools/checks/consumers.sh <files...>

[ -n "$LUNATIK_CONSUMERS" ] || exit 0

source "$(dirname "$0")/modules.sh"

modules=$(for f in "$@"; do reaching_modules "$f"; done | sort -u)
[ -n "$modules" ] || exit 0

found=""
for m in $modules; do
	for dir in $(echo "$LUNATIK_CONSUMERS" | tr ':' ' '); do
		[ -d "$dir" ] || continue
		hits=$(grep -rlE "require\([\"']${m//./\\.}(\.[a-z0-9_.]+)?[\"']\)" "$dir" --include='*.lua' 2>/dev/null)
		[ -n "$hits" ] && found="$found\n  $m: $(echo $hits | tr '\n' ' ')"
	done
done

[ -n "$found" ] || exit 0
echo "Out-of-tree consumers load a binding this change touches:"
printf "$found\n"
echo "Read them before narrowing what it reports, and say in the pull request what their maintainer must change."

