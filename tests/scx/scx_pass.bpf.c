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

struct luascx_task_class {
	u64 dsq;
	u64 slice_ns;
};

static char runtime[] = "tests/scx/pass";

extern int bpf_luascx_run(char *key, size_t key__sz, struct task_struct *task, struct luascx_task_class *cls) __ksym;

s32 BPF_STRUCT_OPS_SLEEPABLE(luascx_init)
{
	scx_bpf_create_dsq(DSQ_DEFAULT, -1);
	return 0;
}

void BPF_STRUCT_OPS(luascx_dispatch, s32 cpu, struct task_struct *prev)
{
	scx_min_dsq_move_to_local(DSQ_DEFAULT);
}

void BPF_STRUCT_OPS(luascx_enqueue, struct task_struct *p, u64 enq_flags)
{
	struct luascx_task_class cls;

	int ret = bpf_luascx_run(runtime, sizeof(runtime), p, &cls);

	if (ret) {
		cls.dsq = DSQ_DEFAULT;
		cls.slice_ns = SCX_SLICE_DFL;
	}
	scx_min_dsq_insert(p, cls.dsq, cls.slice_ns, enq_flags);
}

SEC(".struct_ops")
struct sched_ext_ops luascx_ops = {
	.init       = (void *)luascx_init,
	.dispatch   = (void *)luascx_dispatch,
	.enqueue    = (void *)luascx_enqueue,
	.name       = "luascx",
};

char _license[] SEC("license") = "Dual MIT/GPL";

