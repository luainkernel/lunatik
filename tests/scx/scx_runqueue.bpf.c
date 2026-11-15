/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include "scx_min.bpf.h"

struct luascx_task_class {
	u64 dsq;
	u64 slice_ns;
};

/* runqueue.lua's four steps, then one call that logs `no callback attached`: more would rate limit a next run's */
#define RUNQUEUE_CALLS	5

static char runtime[] = "tests/scx/runqueue";
static u32 calls;

extern int bpf_luascx_run(char *key, size_t key__sz, struct task_struct *task, struct luascx_task_class *cls) __ksym;

/* dispatches nothing, so that a wakeup reaches enqueue even where an idle CPU would take the task */
s32 BPF_STRUCT_OPS(runqueue_select_cpu, struct task_struct *p, s32 prev_cpu, u64 wake_flags)
{
	return prev_cpu;
}

/* the callback's decision is not what the case reads: every task takes the global queue */
void BPF_STRUCT_OPS(runqueue_enqueue, struct task_struct *p, u64 enq_flags)
{
	struct luascx_task_class cls;

	if (calls < RUNQUEUE_CALLS) {
		__sync_fetch_and_add(&calls, 1);
		bpf_luascx_run(runtime, sizeof(runtime), p, &cls);
	}
	scx_min_dsq_insert(p, SCX_DSQ_GLOBAL, SCX_SLICE_DFL, enq_flags);
}

SEC(".struct_ops")
struct sched_ext_ops runqueue_ops = {
	.select_cpu = (void *)runqueue_select_cpu,
	.enqueue    = (void *)runqueue_enqueue,
	.name       = "luascx_runqueue",
};

char _license[] SEC("license") = "Dual MIT/GPL";

