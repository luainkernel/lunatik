/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

extern int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *ctx,
		void *arg, size_t arg__sz) __ksym;

static char runtime[] = "tests/xdp/pass";

SEC("xdp")
int test_xdp_pass(struct xdp_md *ctx)
{
	__u32 magic = 0x4C554E41; /* "LUNA", asserted by pass.lua */
	int ret;
	ret = bpf_luaxdp_run(runtime, sizeof(runtime), ctx, &magic, sizeof(magic));
	return ret < 0 ? XDP_PASS : ret;
}

char LICENSE[] SEC("license") = "GPL";

