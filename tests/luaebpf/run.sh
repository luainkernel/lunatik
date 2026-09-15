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
for t in host pass lineinfo arith divzero branch refuse; do
	echo "${SEP}# --- $t.sh ---"
	SEP=$'\n'
	bash "$DIR/$t.sh" || FAILED=$((FAILED+1))
done

exit $FAILED

