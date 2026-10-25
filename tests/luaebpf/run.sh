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
CASES="host object types order pass lineinfo arith divzero branch forconst forvar call"
CASES="$CASES btfview ctx packet bounds nonlinear mapget mapset struct refuse budget"
CASES="$CASES load stop unload undo notarget verifierlog callback miss partition nobtf"

for t in $CASES; do
	echo "${SEP}# --- $t.sh ---"
	SEP=$'\n'
	bash "$DIR/$t.sh" || FAILED=$((FAILED+1))
done

exit $FAILED

