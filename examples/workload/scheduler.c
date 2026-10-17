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

struct luascx_task_class {
	u64 dsq;
	u64 slice_ns;
};

struct task_entry {
	struct luascx_task_class cls;
	u64 exec_id;
};

static char runtime[] = "examples/workload/workload";

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 10240);
	__type(key, pid_t);
	__type(value, struct task_entry);
} task_classes SEC(".maps");

extern int bpf_luascx_run(char *key, size_t key__sz, struct task_struct *task, struct luascx_task_class *cls) __ksym;

s32 BPF_STRUCT_OPS_SLEEPABLE(workload_init)
{
	scx_bpf_create_dsq(DSQ_REALTIME, -1);
	scx_bpf_create_dsq(DSQ_BATCH, -1);
	scx_bpf_create_dsq(DSQ_DEFAULT, -1);
	return 0;
}

void BPF_STRUCT_OPS(workload_dispatch, s32 cpu, struct task_struct *prev)
{
	if (!scx_min_dsq_move_to_local(DSQ_REALTIME) && !scx_min_dsq_move_to_local(DSQ_DEFAULT))
		scx_min_dsq_move_to_local(DSQ_BATCH);
}

void BPF_STRUCT_OPS(workload_enqueue, struct task_struct *p, u64 enq_flags)
{
	pid_t pid = p->pid;
	struct task_entry *cached = bpf_map_lookup_elem(&task_classes, &pid);

	if (cached && cached->exec_id == p->self_exec_id) { /* an exec changes the command the policy matched */
		scx_min_dsq_insert(p, cached->cls.dsq, cached->cls.slice_ns, enq_flags);
		return;
	}

	struct task_entry entry = {
		.cls = { .dsq = DSQ_DEFAULT, .slice_ns = SCX_SLICE_DFL },
		.exec_id = p->self_exec_id,
	};

	if (bpf_luascx_run(runtime, sizeof(runtime), p, &entry.cls) == 0)
		bpf_map_update_elem(&task_classes, &pid, &entry, BPF_ANY);
	scx_min_dsq_insert(p, entry.cls.dsq, entry.cls.slice_ns, enq_flags);
}

void BPF_STRUCT_OPS(workload_exit_task, struct task_struct *p, struct scx_exit_task_args *args)
{
	pid_t pid = p->pid;
	bpf_map_delete_elem(&task_classes, &pid);
}

SEC(".struct_ops")
struct sched_ext_ops workload_ops = {
	.init       = (void *)workload_init,
	.dispatch   = (void *)workload_dispatch,
	.enqueue    = (void *)workload_enqueue,
	.exit_task  = (void *)workload_exit_task,
	.name       = "workload",
};

char _license[] SEC("license") = "Dual MIT/GPL";

