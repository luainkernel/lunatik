#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all luaebpf tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/luaebpf/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

SEP=""
SUITES="host pass lineinfo arith divzero branch forconst forvar while iter call"
SUITES="$SUITES btfview ctx packet bounds getstring strcmp strkey strret mapget mapset struct refuse budget"
SUITES="$SUITES load stop undo notarget verifierlog callback miss partition report nobtf"
SUITES="$SUITES example_filter"

for t in $SUITES; do
	echo "${SEP}# --- $t.sh ---"
	SEP=$'\n'
	bash "$DIR/$t.sh" || FAILED=$((FAILED+1))
done

exit $FAILED

