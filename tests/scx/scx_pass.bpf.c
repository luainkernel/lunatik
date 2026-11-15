/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include "scx_min.bpf.h"

#define DSQ_DEFAULT 0
#define CLS_UNSET 0x5c5c5c5c5c5c5c5cULL

struct luascx_task_class {
	u64 dsq;
	u64 slice_ns;
};

/* what the kfunc returned and left in cls at the first enqueue of a task named scx_*, by its comm */
struct record {
	s64 ret;
	u64 dsq;
	u64 slice_ns;
};

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 16);
	__type(key, char[TASK_COMM_LEN]);
	__type(value, struct record);
	__uint(pinning, LIBBPF_PIN_BY_NAME);
} scx_record SEC(".maps");

static char runtime[] = "tests/scx/pass";
static const char tag[] = "scx_";

extern int bpf_luascx_run(char *key, size_t key__sz, struct task_struct *task, struct luascx_task_class *cls) __ksym;

static void record(struct task_struct *p, int ret, struct luascx_task_class *cls)
{
	char comm[TASK_COMM_LEN] = {};
	struct record rec = {.ret = ret, .dsq = cls->dsq, .slice_ns = cls->slice_ns};

	bpf_probe_read_kernel_str(comm, sizeof(comm), p->comm);
	if (bpf_strncmp(comm, sizeof(tag) - 1, tag) == 0)
		bpf_map_update_elem(&scx_record, comm, &rec, BPF_NOEXIST);
}

s32 BPF_STRUCT_OPS_SLEEPABLE(luascx_init)
{
	scx_bpf_create_dsq(DSQ_DEFAULT, -1);
	return 0;
}

/* dispatches nothing, so that a wakeup reaches enqueue even where an idle CPU would take the task */
s32 BPF_STRUCT_OPS(luascx_select_cpu, struct task_struct *p, s32 prev_cpu, u64 wake_flags)
{
	return prev_cpu;
}

void BPF_STRUCT_OPS(luascx_dispatch, s32 cpu, struct task_struct *prev)
{
	scx_min_dsq_move_to_local(DSQ_DEFAULT);
}

void BPF_STRUCT_OPS(luascx_enqueue, struct task_struct *p, u64 enq_flags)
{
	struct luascx_task_class cls = {.dsq = CLS_UNSET, .slice_ns = CLS_UNSET};

	int ret = bpf_luascx_run(runtime, sizeof(runtime), p, &cls);

	record(p, ret, &cls);
	if (ret) {
		cls.dsq = DSQ_DEFAULT;
		cls.slice_ns = SCX_SLICE_DFL;
	}
	scx_min_dsq_insert(p, cls.dsq, cls.slice_ns, enq_flags);
}

SEC(".struct_ops")
struct sched_ext_ops luascx_ops = {
	.init       = (void *)luascx_init,
	.select_cpu = (void *)luascx_select_cpu,
	.dispatch   = (void *)luascx_dispatch,
	.enqueue    = (void *)luascx_enqueue,
	.name       = "luascx",
};

char _license[] SEC("license") = "Dual MIT/GPL";

