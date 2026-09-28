/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

extern int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *skb,
		void *arg, size_t arg__sz) __ksym;

static char runtime[] = "tests/tc/nonlinear";

int const TC_ACT_OK = 0;

SEC("classifier")
int test_tc_nonlinear(struct __sk_buff *skb)
{
	__u32 pulled = 0;
	int ret;

	bpf_luatc_run(runtime, sizeof(runtime), skb, &pulled, sizeof(pulled));
	if (bpf_skb_pull_data(skb, skb->len) < 0)
		return TC_ACT_OK;

	pulled = 1;
	ret = bpf_luatc_run(runtime, sizeof(runtime), skb, &pulled, sizeof(pulled));
	return ret < 0 ? TC_ACT_OK : ret;
}

char _license[] SEC("license") = "Dual MIT/GPL";

