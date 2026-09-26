#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all device tests.
#
# Usage: sudo bash tests/device/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
TESTS="held returns file"
FAILED=0

SEP=$'\n'
for t in $TESTS; do
	echo "${SEP}# --- $t.sh ---"
	bash "$DIR/$t.sh" || FAILED=$((FAILED+1))
done

exit $FAILED

