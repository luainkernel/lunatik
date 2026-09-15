#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all examples tests and reports aggregated KTAP results.
#
# An example is driven here only if it binds loopback and arms no kernel hook:
# tools/checks/example-guard.sh does not see a spawn issued from inside a suite,
# so what a driven example may do to the host is a criterion written down here.
#
# Usage: sudo bash tests/examples/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

SEP=""
for t in "$DIR"/shared.sh; do
	echo "${SEP}# --- $(basename "$t") ---"
	SEP=$'\n'
	bash "$t" || FAILED=$((FAILED+1))
done

exit $FAILED

