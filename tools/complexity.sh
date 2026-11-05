#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Prints the complexity label a pull request carries, read from the lines it adds as GitHub counts
# them against its base: up to 40 `complexity: small`, up to 150 `complexity: medium`, past that
# `complexity: large`. The maintainer picks what he reviews by that label, the small first; the lines
# a change removes do not count, since a removal reads at a glance.
#
# Usage: GH_TOKEN=... bash tools/complexity.sh <number>

[ $# -eq 1 ] || { echo "usage: $0 <number>" >&2; exit 2; }

added=$(gh api "repos/luainkernel/lunatik/pulls/$1" -q .additions) || exit 1
if [ "$added" -le 40 ]; then
	size=small
elif [ "$added" -le 150 ]; then
	size=medium
else
	size=large
fi
echo "complexity: $size"

