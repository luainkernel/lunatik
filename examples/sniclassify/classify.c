/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

extern int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *skb,
		void *arg, size_t arg__sz) __ksym;

static char runtime[] = "examples/sniclassify/sni";

int const TC_ACT_OK = 0;

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 65536);
	__type(key, __u32);
	__type(value, __u32);
} flow_cache SEC(".maps");

SEC("classifier")
int classify(struct __sk_buff *skb)
{
	__u32 key = skb->hash;

	__u32 *priority = bpf_map_lookup_elem(&flow_cache, &key);
	if (priority) {
		skb->priority = *priority;
		return TC_ACT_OK;
	}

	void *data_end = (void *)(long)skb->data_end;
	void *data = (void *)(long)skb->data;
	struct iphdr *ip = data + sizeof(struct ethhdr);

	if (ip + 1 > (struct iphdr *)data_end)
		goto pass;

	if (ip->protocol != IPPROTO_TCP)
		goto pass;

	struct tcphdr *tcp = (void *)ip + (ip->ihl * 4);
	if (tcp + 1 > (struct tcphdr *)data_end)
		goto pass;

	if (bpf_ntohs(tcp->dest) != 443 || !tcp->psh)
		goto pass;

	void *payload = (void *)tcp + (tcp->doff * 4);
	if (payload > data_end)
		goto pass;

	__u32 offset = payload - data;
	int action = bpf_luatc_run(runtime, sizeof(runtime), skb, &offset, sizeof(offset));
	if (action < 0)
		return TC_ACT_OK;

	__u32 prio = skb->priority;
	bpf_map_update_elem(&flow_cache, &key, &prio, BPF_ANY);
	return action;
pass:
	return TC_ACT_OK;
}

char _license[] SEC("license") = "Dual MIT/GPL";

