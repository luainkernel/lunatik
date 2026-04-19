#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all notifier regression tests.
#
# Usage: sudo bash tests/notifier/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

SEP=$'\n'
for t in "$DIR"/context_mismatch.sh; do
	echo "${SEP}# --- $(basename "$t") ---"
	bash "$t" || FAILED=$((FAILED+1))
done

exit $FAILED

