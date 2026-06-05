#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all skb tests.
#
# Usage: sudo bash tests/skb/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

SEP=""
for t in "$DIR"/connmark.sh; do
	echo "${SEP}# --- $(basename "$t") ---"
	SEP=$'\n'
	bash "$t" || FAILED=$((FAILED+1))
done

exit $FAILED

