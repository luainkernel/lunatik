/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*
* Minimal sched_ext struct_ops helpers.
*
* This intentionally does NOT include scx/common.bpf.h. That header pulls
* in compat.bpf.h and cid.bpf.h, which define fallback/polyfill kfuncs for
* kernels that lack native support for certain scx kfuncs.
*/

#ifndef __SCX_MIN_BPF_H
#define __SCX_MIN_BPF_H

#define BPF_STRUCT_OPS(name, args...)						\
SEC("struct_ops/"#name)								\
BPF_PROG(name, ##args)

#define BPF_STRUCT_OPS_SLEEPABLE(name, args...)				\
SEC("struct_ops.s/"#name)							\
BPF_PROG(name, ##args)

#endif

