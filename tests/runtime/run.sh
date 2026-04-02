#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all runtime tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/runtime/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

TESTS=(
	refcnt_leak.sh
	resume_shared.sh
	resume_mailbox.sh
	rcu_shared.sh
	opt_guards.sh
	opt_skb_single.sh
	require_cloneobject.sh
)

SEP=""
for t in "${TESTS[@]}"; do
	echo "${SEP}# --- $t ---"
	SEP=$'\n'
	bash "$DIR/$t" || FAILED=$((FAILED+1))
done

exit $FAILED

