#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names the commits of a rev-range that wait for a squash, a fixup!, amend! or squash! subject, and
# exits 1 when there is one: a pull request merged with one lands it on master, as #1788 did. The
# Checks workflow runs it over a pull request, so the run stays red until the squash.
#
# Usage: bash tools/checks/fixups.sh <base>..<head>

[ -n "$1" ] || { echo "usage: fixups.sh <base>..<head>" >&2; exit 2; }
pending=$(git log --format='%h %s' "$1" | grep -E '^[0-9a-f]+ (fixup|amend|squash)! ')
[ -n "$pending" ] || exit 0
echo "fixups: these wait for the squash, which folds them before the merge:"
printf '%s\n' "$pending" | sed 's/^/  /'
exit 1

