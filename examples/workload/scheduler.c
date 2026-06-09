/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include <scx/common.bpf.h>

#define DSQ_REALTIME 0
#define DSQ_BATCH    1
#define DSQ_DEFAULT  2

struct task_class {
	s32 dsq;
	u64 slice_ns;
};

static char runtime[] = "examples/workload/workload";

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 10240);
	__type(key, pid_t);
	__type(value, struct task_class);
} task_classes SEC(".maps");

extern int bpf_luasched_run(const char *key, size_t key__sz, struct task_struct *task, struct task_class *cls) __ksym;

s32 BPF_STRUCT_OPS_SLEEPABLE(luasched_init)
{
	scx_bpf_create_dsq(DSQ_REALTIME, -1);
	scx_bpf_create_dsq(DSQ_BATCH, -1);
	scx_bpf_create_dsq(DSQ_DEFAULT, -1);
	return 0;
}

void BPF_STRUCT_OPS(luasched_dispatch, s32 cpu, struct task_struct *prev)
{
	if (!scx_bpf_dsq_move_to_local(DSQ_REALTIME)) {
		if (!scx_bpf_dsq_move_to_local(DSQ_BATCH)) {
			scx_bpf_dsq_move_to_local(DSQ_DEFAULT);
		}
	}
}

void BPF_STRUCT_OPS(luasched_enqueue, struct task_struct *p, u64 enq_flags)
{
	pid_t pid = p->pid;
	struct task_class *cls;

	cls = bpf_map_lookup_elem(&task_classes, &pid);
	if (cls) {
		scx_bpf_dsq_insert(p, cls->dsq, cls->slice_ns, 0);
		return;
	}

	struct task_class received_cls = { .dsq = -1, .slice_ns = -1 };

	int ret = bpf_luasched_run(runtime, sizeof(runtime), p, &received_cls);

	if (ret < 0) {
		received_cls.dsq = DSQ_DEFAULT;
		received_cls.slice_ns = SCX_SLICE_DFL;
	}

	bpf_map_update_elem(&task_classes, &pid, &received_cls, BPF_ANY);
	scx_bpf_dsq_insert(p, received_cls.dsq, received_cls.slice_ns, 0);
}

void BPF_STRUCT_OPS(luasched_exit_task, struct task_struct *p, struct scx_exit_task_args *args)
{
	pid_t pid = p->pid;
	bpf_map_delete_elem(&task_classes, &pid);
}

SEC(".struct_ops")
struct sched_ext_ops luasched_ops = {
	.init       = (void *)luasched_init,
	.dispatch   = (void *)luasched_dispatch,
	.enqueue    = (void *)luasched_enqueue,
	.exit_task  = (void *)luasched_exit_task,
	.name       = "luasched",
};

char _license[] SEC("license") = "GPL";

