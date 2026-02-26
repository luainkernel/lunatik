/*
 * SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

extern int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *skb, void *arg, size_t arg__sz) __ksym;

static char runtime[] = "examples/filter/sni_tc";

#define ETH_P_IP	0x0800
#define TC_ACT_OK	0
#define TC_ACT_SHOT	2

struct bpf_luatc_arg {
	__u16 offset;
} __attribute__((packed));

SEC("tc")
int filter_https(struct __sk_buff *skb)
{
    struct bpf_luatc_arg arg = {0};
    int action = bpf_luatc_run(runtime, sizeof(runtime), skb, &arg, sizeof(arg));

    return action;
}

char _license[] SEC("license") = "Dual MIT/GPL";
