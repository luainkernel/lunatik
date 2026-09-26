#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A mechanism built over a kernel primitive is compared with the kernel's own
# answer to the same problem before it is written, and the commit says which
# one. #1158 answered a walk whose callback sleeps under RCU with a per-bucket
# snapshot of the keys, a re-lookup of each and then a deferred-free list, over
# four review rounds and a crashed host, when Documentation/RCU/whatisRCU.rst
# answers "Will readers need to block? If so, you need SRCU" in one line and
# lib/rhashtable.c states what a walk that drops the lock between elements gets
# instead.
#
# This one reads commits, not files, since the comparison belongs in the body.
# A commit that adds primitives of a family (RCU, locking, reference counts,
# deferred work) together with a new function or field, the shape of a
# mechanism and not of a one-line fix, is named when its body carries neither a
# Documentation/ path nor one of the family's own facilities. Over the last 300
# commits of master it fires on two, the lock operations of lunatik_lock.h and
# the kprobe a percpu script's runtimes share, both mechanisms of the kind it
# asks about. Heuristic: it nudges a review, it does not rewrite.
#
# Usage: bash tools/checks/kernel-answer.sh <commit or range>...   (default HEAD)

primitives_rcu='\b(rcu_read_lock|call_rcu|kfree_rcu|kvfree_rcu|synchronize_rcu|rcu_dereference|rcu_assign_pointer|(h?list)_[a-z_]*_rcu|srcu_read_lock|call_srcu|synchronize_srcu)\b'
answers_rcu='Documentation/RCU|\bSRCU\b|srcu_|rhashtable_walk|rcu_barrier|rcuref'
docs_rcu='Documentation/RCU/whatisRCU.rst (which RCU to use), Documentation/RCU/listRCU.rst, lib/rhashtable.c (a walk that drops the lock)'

primitives_locking='\b(spin_lock|spin_trylock|raw_spin_lock|mutex_lock|mutex_trylock|read_lock|write_lock|seqcount_|read_seqbegin|down_read|down_write|rt_mutex_lock|local_lock)\b'
answers_locking='Documentation/locking|seqcount|seqlock|percpu_rw_semaphore|\bRCU\b|local_lock|rwsem'
docs_locking='Documentation/locking/locktypes.rst, Documentation/locking/seqlock.rst, Documentation/kernel-hacking/locking.rst'

primitives_refcount='\b(kref_init|kref_get|kref_put|kref_get_unless_zero|refcount_inc|refcount_dec|refcount_inc_not_zero|atomic_inc|atomic_dec|atomic_cmpxchg|atomic_fetch_|atomic_dec_and_test)\b'
answers_refcount='Documentation/core-api/(kref|refcount)|\bkref\b|refcount_t|percpu_ref|rcuref'
docs_refcount='Documentation/core-api/kref.rst, Documentation/core-api/refcount-vs-atomic.rst'

primitives_deferral='\b(INIT_WORK|INIT_DELAYED_WORK|queue_work|schedule_work|schedule_delayed_work|timer_setup|mod_timer|tasklet_init|tasklet_schedule|irq_work_queue|kthread_run|kthread_create)\b'
answers_deferral='Documentation/core-api/workqueue|Documentation/timers|workqueue|delayed_work|irq_work|kthread_worker|tasklet'
docs_deferral='Documentation/core-api/workqueue.rst, Documentation/timers/, Documentation/core-api/irq/'

families="rcu locking refcount deferral"

# a function definition at column zero, a definer macro, or a declaration at one tab with no initializer
mechanism='^\+((static |extern )?(inline |noinline )?[A-Za-z_][A-Za-z0-9_ ]*[ *]+[A-Za-z_][A-Za-z0-9_]*\(.*\)$|(DEFINE_[A-Z_]+|LIST_HEAD|DECLARE_[A-Z_]+)\(|\t(struct |unsigned |bool |int |long |size_t |u8 |u16 |u32 |u64 |atomic_t |refcount_t |spinlock_t |struct mutex |lunatik_)[A-Za-z0-9_ *]*;$)'

status=0

for commit in $(git rev-list --no-walk "${@:-HEAD}"); do
	added=$(git show --format= --unified=0 "$commit" -- '*.c' '*.h' | grep -E '^\+[^+]' || true)
	[ -n "$added" ] || continue
	grep -qE "$mechanism" <<< "$added" || continue
	body=$(git show -s --format=%B "$commit")

	for family in $families; do
		primitives=primitives_$family answers=answers_$family docs=docs_$family
		grep -qE "${!primitives}" <<< "$added" || continue
		grep -qE "${!answers}" <<< "$body" && continue

		subject=$(git show -s --format=%s "$commit")
		printf '%s "%s" builds over %s primitives and names no kernel answer: read %s and say which facility the shape was compared with\n' \
			"${commit:0:9}" "$subject" "$family" "${!docs}"
		status=1
	done
done

[ $status -eq 0 ] || echo "a mechanism over a kernel primitive names in its body the kernel's own answer to the problem, or the Documentation/ page that has none"
exit $status

