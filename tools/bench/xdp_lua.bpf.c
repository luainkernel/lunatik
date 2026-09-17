/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

#include "bench.bpf.h"

extern int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *ctx,
		void *arg, size_t arg__sz) __ksym;

static char runtime[] = LUNATIK_BENCH_RUNTIME;

SEC("xdp")
int bench_xdp_lua(struct xdp_md *ctx)
{
	bench_count(BENCH_PROCESSED);
	int ret = bpf_luaxdp_run(runtime, sizeof(runtime), ctx, NULL, 0);
	if (ret < 0) {
		bench_count(BENCH_REFUSED);
		return XDP_ABORTED; /* a PASS here would measure the native path under a Lua label */
	}
	return ret;
}

char _license[] SEC("license") = "Dual MIT/GPL";

