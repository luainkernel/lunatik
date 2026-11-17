/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

extern void bpf_lunatik_log(char *msg, size_t msg__sz) __ksym;

#define LINE "xdp log: a line from the program"

/* the bytes past the size it passes are the program's, which the kfunc must not read */
static char message[] = LINE " and bytes past its size";

SEC("xdp")
int test_xdp_log(struct xdp_md *ctx)
{
	bpf_lunatik_log(message, sizeof(LINE) - 1);
	return XDP_PASS;
}

char _license[] SEC("license") = "Dual MIT/GPL";

