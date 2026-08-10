/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

extern int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *ctx,
		void *arg, size_t arg__sz) __ksym;

static char runtime[] = "tests/xdp/zerokey";

SEC("xdp")
int test_xdp_zerokey(struct xdp_md *ctx)
{
	/* drop on rejection, so a working guard blocks the ping and proves the kfunc ran */
	int ret;
	ret = bpf_luaxdp_run(runtime, 0, ctx, NULL, 0);
	return ret < 0 ? XDP_DROP : XDP_PASS;
}

char LICENSE[] SEC("license") = "GPL";

