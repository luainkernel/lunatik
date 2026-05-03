/* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#ifndef LUNATIK_BPF_H
#define LUNATIK_BPF_H

#include "lunatik.h"
#include "lua.h"

struct lunatik_bpf_call {
	lua_CFunction			registry_key;
	void					*ctx;
};

int lunatik_bpf_run(
	lunatik_object_t *runtimes,
	lua_CFunction registry_key,
	void *ctx);

#endif

