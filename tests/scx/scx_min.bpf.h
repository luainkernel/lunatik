/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*
* Minimal sched_ext struct_ops helpers, in place of scx/common.bpf.h, whose
* compat layer pulls in more than this program uses.
*/

#ifndef __SCX_MIN_BPF_H
#define __SCX_MIN_BPF_H

#define BPF_STRUCT_OPS(name, args...)						\
SEC("struct_ops/"#name)								\
BPF_PROG(name, ##args)

#define BPF_STRUCT_OPS_SLEEPABLE(name, args...)				\
SEC("struct_ops.s/"#name)							\
BPF_PROG(name, ##args)

s32 scx_bpf_create_dsq(u64 dsq_id, s32 node) __ksym;

/* 6.12 names the insert and move kfuncs scx_bpf_dispatch and scx_bpf_consume, 6.13 added
 * scx_bpf_dsq_insert and scx_bpf_dsq_move_to_local and 6.17 dropped the old pair, so both
 * are weak and the one the running kernel has is called */
void scx_bpf_dsq_insert(struct task_struct *p, u64 dsq_id, u64 slice, u64 enq_flags) __ksym __weak;
void scx_bpf_dispatch(struct task_struct *p, u64 dsq_id, u64 slice, u64 enq_flags) __ksym __weak;
bool scx_bpf_dsq_move_to_local(u64 dsq_id) __ksym __weak;
bool scx_bpf_consume(u64 dsq_id) __ksym __weak;

static inline void scx_min_dsq_insert(struct task_struct *p, u64 dsq_id, u64 slice, u64 enq_flags)
{
	if (bpf_ksym_exists(scx_bpf_dsq_insert))
		scx_bpf_dsq_insert(p, dsq_id, slice, enq_flags);
	else
		scx_bpf_dispatch(p, dsq_id, slice, enq_flags);
}

static inline bool scx_min_dsq_move_to_local(u64 dsq_id)
{
	return bpf_ksym_exists(scx_bpf_dsq_move_to_local) ? scx_bpf_dsq_move_to_local(dsq_id) : scx_bpf_consume(dsq_id);
}

#endif

