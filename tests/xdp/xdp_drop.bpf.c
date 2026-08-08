/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

extern int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *ctx,
		void *arg, size_t arg__sz) __ksym;

static char runtime[] = "tests/xdp/drop";

SEC("xdp")
int test_xdp_drop(struct xdp_md *ctx)
{
	int ret;
	ret = bpf_luaxdp_run(runtime, sizeof(runtime), ctx, NULL, 0);
	return ret < 0 ? XDP_PASS : ret;
}

char LICENSE[] SEC("license") = "GPL";

