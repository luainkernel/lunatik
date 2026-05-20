/* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */
#ifndef LUNATIK_BPF_H
#define LUNATIK_BPF_H

#include "lunatik.h"

/**
 * Fetches the environment context from runtime registry
 * Sets out_ptr to the objects private pointer
 */
#define lunatik_bpf_get_env(L, env_key, out_ptr) do { \
	if (lunatik_getregistry((L), (env_key)) != LUA_TUSERDATA) { \
		lua_pop((L), 1); \
		pr_err("couldn't find the context object\n"); \
		return -1; \
	} \
	lunatik_object_t *obj = (lunatik_object_t *)lunatik_toobject((L), -1); \
	(out_ptr) = obj->private; \
} while (0)

#endif

