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
	resume_results.sh
	resume_foreign.sh
	resume_percpu.sh
	foreign_method.sh
	foreign_checker.sh
	resume_mailbox.sh
	rcu_shared.sh
	opt_guards.sh
	opt_skb_single.sh
	require_cloneobject.sh
	require_reopen.sh
	module_owner.sh
	percpu.sh
	percpu_object.sh
	percpu_refuse.sh
	spawn_refuse.sh
	run_context.sh
	spawn_suffix.sh
	spawn_name.sh
	percpu_netfilter.sh
	collected.sh
	closing.sh
	self_stop.sh
	errobj.sh
	killable.sh
)

SEP=""
for t in "${TESTS[@]}"; do
	echo "${SEP}# --- $t ---"
	SEP=$'\n'
	bash "$DIR/$t" || FAILED=$((FAILED+1))
done

exit $FAILED

