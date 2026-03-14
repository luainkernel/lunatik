#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all socket tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/socket/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

SEP=""
for t in "$DIR"/unix/run.sh; do
	echo "${SEP}# --- unix ---"
	SEP=$'\n'
	bash "$t" || FAILED=$((FAILED+1))
done

exit $FAILED

