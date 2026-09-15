/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

#include "bench.bpf.h"

SEC("xdp")
int bench_xdp_native(struct xdp_md *ctx)
{
	bench_count(BENCH_PROCESSED);
	return XDP_PASS;
}

char _license[] SEC("license") = "Dual MIT/GPL";

