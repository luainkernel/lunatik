/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

#define SIZE	(1 << 20)	/* the fifos close.lua creates */

static const char task[] = "lunatik";	/* the CLI that runs it */

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} refused SEC(".maps");

SEC("kprobe/should_fail_alloc_page")
int BPF_KPROBE(fallback, gfp_t gfp, unsigned int order)
{
	char comm[TASK_COMM_LEN];
	__u32 key = 0;

	if (((__u64)PAGE_SIZE << order) != SIZE || bpf_get_current_comm(comm, sizeof(comm)) != 0)
		return 0;
	for (int i = 0; i < sizeof(task); i++)
		if (comm[i] != task[i])
			return 0;

	__u64 *count = bpf_map_lookup_elem(&refused, &key);
	if (count != NULL)
		__sync_fetch_and_add(count, 1);
	bpf_override_return(ctx, 1);
	return 0;
}

char _license[] SEC("license") = "Dual MIT/GPL";

