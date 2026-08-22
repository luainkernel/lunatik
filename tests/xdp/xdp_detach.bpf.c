/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

extern int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *ctx,
		void *arg, size_t arg__sz) __ksym;

static char runtime[] = "tests/xdp/detach";

SEC("xdp")
int test_xdp_detach(struct xdp_md *ctx)
{
	int ret;
	ret = bpf_luaxdp_run(runtime, sizeof(runtime), ctx, NULL, 0);
	return ret < 0 ? XDP_PASS : ret;
}

char _license[] SEC("license") = "Dual MIT/GPL";

