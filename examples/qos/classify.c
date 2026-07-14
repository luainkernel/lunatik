/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

extern int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *skb, void *arg, size_t arg__sz) __ksym;

static char runtime[] = "examples/qos/tc";

int const TC_ACT_OK = 0;

SEC("classifier")
int classify(struct __sk_buff *skb)
{
	int action = bpf_luatc_run(runtime, sizeof(runtime), skb, NULL, 0);
	return action < 0 ? TC_ACT_OK : action;
}

char _license[] SEC("license") = "Dual MIT/GPL";

