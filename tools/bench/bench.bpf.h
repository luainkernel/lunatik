/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*
* The counters every bench program keeps. One increment on the path a packet
* takes, so what the map costs cancels between rows; a Lua row counts the kfunc's
* refusal rather than its dispatch, so its measured path costs what the native
* one does and a row that never reached Lua is still visible.
*/

#ifndef __BENCH_BPF_H
#define __BENCH_BPF_H

#define BENCH_PROCESSED	0
#define BENCH_REFUSED	1

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 2);
	__type(key, __u32);
	__type(value, __u64);
} bench_counters SEC(".maps");

static inline void bench_count(__u32 slot)
{
	__u64 *counter = bpf_map_lookup_elem(&bench_counters, &slot);

	if (counter)
		*counter += 1;
}

#endif

