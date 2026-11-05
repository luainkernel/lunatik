/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include "scx_min.bpf.h"

#define DSQ_REALTIME 0
#define DSQ_BATCH    1
#define DSQ_DEFAULT  2

/* the upper bound for a slice the policy may ask for: a typo must not give a task the CPU for seconds */
#define MAX_SLICE_NS (100ULL * 1000 * 1000)

struct luascx_task_class {
	u64 dsq;
	u64 slice_ns;
};

struct task_entry {
	struct luascx_task_class cls;
	u64 exec_id;
};

static char runtime[] = "examples/workload/workload";

/* per-task storage is freed with the task: no pid reuse, no size cap and no exit hook */
struct {
	__uint(type, BPF_MAP_TYPE_TASK_STORAGE);
	__uint(map_flags, BPF_F_NO_PREALLOC);
	__type(key, int);
	__type(value, struct task_entry);
} task_classes SEC(".maps");

/* one rotation counter per CPU, so the dispatch path shares no cache line and needs no atomic */
struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, u32);
	__type(value, u32);
} turns SEC(".maps");

extern int bpf_luascx_run(char *key, size_t key__sz, struct task_struct *task, struct luascx_task_class *cls) __ksym;
extern s32 scx_bpf_select_cpu_dfl(struct task_struct *p, s32 prev_cpu, u64 wake_flags, bool *is_idle) __ksym;

s32 BPF_STRUCT_OPS_SLEEPABLE(workload_init)
{
	scx_bpf_create_dsq(DSQ_REALTIME, -1);
	scx_bpf_create_dsq(DSQ_BATCH, -1);
	scx_bpf_create_dsq(DSQ_DEFAULT, -1);
	return 0;
}

/* leaves the insert to workload_enqueue, so a task that wakes on an idle CPU meets the policy too */
s32 BPF_STRUCT_OPS(workload_select_cpu, struct task_struct *p, s32 prev_cpu, u64 wake_flags)
{
	bool is_idle = false;

	return scx_bpf_select_cpu_dfl(p, prev_cpu, wake_flags, &is_idle);
}

#define NR_LEADS 8

/* realtime leads 5 of the 8 dispatches, default 2 and batch 1, so no busy queue starves the ones below */
static const u64 leads[NR_LEADS] = {
	DSQ_REALTIME, DSQ_DEFAULT, DSQ_REALTIME, DSQ_BATCH, DSQ_REALTIME, DSQ_DEFAULT, DSQ_REALTIME, DSQ_REALTIME,
};

void BPF_STRUCT_OPS(workload_dispatch, s32 cpu, struct task_struct *prev)
{
	u32 zero = 0, index = 0;
	u32 *turn = bpf_map_lookup_elem(&turns, &zero);

	if (turn)
		index = (*turn)++ % NR_LEADS;

	if (scx_min_dsq_move_to_local(leads[index]))
		return;
	if (!scx_min_dsq_move_to_local(DSQ_REALTIME) && !scx_min_dsq_move_to_local(DSQ_DEFAULT))
		scx_min_dsq_move_to_local(DSQ_BATCH);
}

/* the Lua policy is untrusted input: inserting into a DSQ that does not exist aborts the whole scheduler */
static __always_inline void sanitize(struct luascx_task_class *cls)
{
	if (cls->dsq > DSQ_DEFAULT)
		cls->dsq = DSQ_DEFAULT;
	if (!cls->slice_ns)
		cls->slice_ns = SCX_SLICE_DFL;
	else if (cls->slice_ns > MAX_SLICE_NS)
		cls->slice_ns = MAX_SLICE_NS;
}

void BPF_STRUCT_OPS(workload_enqueue, struct task_struct *p, u64 enq_flags)
{
	struct task_entry *cached = bpf_task_storage_get(&task_classes, p, 0, 0);

	if (cached && cached->exec_id == p->self_exec_id) { /* an exec changes the command the policy matched */
		scx_min_dsq_insert(p, cached->cls.dsq, cached->cls.slice_ns, enq_flags);
		return;
	}

	struct task_entry entry = {
		.cls = { .dsq = DSQ_DEFAULT, .slice_ns = SCX_SLICE_DFL },
		.exec_id = p->self_exec_id,
	};

	if (bpf_luascx_run(runtime, sizeof(runtime), p, &entry.cls) == 0) {
		sanitize(&entry.cls);
		cached = bpf_task_storage_get(&task_classes, p, &entry, BPF_LOCAL_STORAGE_GET_F_CREATE);
		if (cached)
			*cached = entry; /* the storage of a task classified before an exec comes back as it was */
	}
	scx_min_dsq_insert(p, entry.cls.dsq, entry.cls.slice_ns, enq_flags);
}

SEC(".struct_ops")
struct sched_ext_ops workload_ops = {
	.init       = (void *)workload_init,
	.select_cpu = (void *)workload_select_cpu,
	.dispatch   = (void *)workload_dispatch,
	.enqueue    = (void *)workload_enqueue,
	.name       = "workload",
};

char _license[] SEC("license") = "Dual MIT/GPL";

