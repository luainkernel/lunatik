/* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */
#ifndef LUNATIK_BPF_H
#define LUNATIK_BPF_H

#include "lunatik.h"

typedef int (*lunatik_bpf_push_t)(lua_State *L, void *ctx);

struct lunatik_bpf_call {
	lua_CFunction      registry_key;
	lunatik_bpf_push_t push_ctx;
	void              *ctx;
};

int lunatik_bpf_run(lunatik_object_t *runtime, lua_CFunction registry_key, lunatik_bpf_push_t push_ctx, void *ctx);

#endif

