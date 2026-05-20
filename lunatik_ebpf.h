/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef LUNATIK_EBPF_H
#define LUNATIK_EBPF_H

#include "lunatik.h"

#define lunatik_ebpf_checkruntimes(runtimes) \
({ \
	const char *key = "runtimes"; \
	if ((runtimes) == NULL) \
		(runtimes) = luarcu_getobject(lunatik_env, key, sizeof(key)); \
	(runtimes) != NULL ? 0 : -1; \
})

#define lunatik_ebpf_lookup(runtimes, key, key_sz) \
({ \
	lunatik_object_t *runtime = NULL; \
	size_t keylen = key_sz - 1; \
	key[keylen] = '\0'; \
	if (unlikely(lunatik_ebpf_checkruntimes(runtimes) != 0)) \
		pr_err("couldn't find _ENV.runtimes\n"); \
	else { \
		runtime = luarcu_getobject((runtimes), (key), keylen); \
		if (runtime == NULL) \
			pr_err("couldn't find runtime '%s'\n", (key)); \
 	} \
	runtime; \
})

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

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0))
#define LUNATIK_EBPF_START() __bpf_kfunc_start_defs()
#define LUNATIK_EBPF_END()   __bpf_kfunc_end_defs()
#else
#define LUNATIK_EBPF_START() \
	__diag_push(); \
	__diag_ignore_all("-Wmissing-prototypes", \
			"Global kfuncs as their definitions will be in BTF")
#define LUNATIK_EBPF_END()   __diag_pop()
#endif

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 9, 0))
#define LUNATIK_BTF_SET_START(name) BTF_KFUNCS_START(name)
#define LUNATIK_BTF_SET_END(name)   BTF_KFUNCS_END(name)
#else
#define LUNATIK_BTF_SET_START(name) BTF_SET8_START(name)
#define LUNATIK_BTF_SET_END(name)   BTF_SET8_END(name)
#endif

#define LUNATIK_EBPF_KFUNC_DEFINE_SET(subsys, kfunc) \
	LUNATIK_BTF_SET_START(bpf_lua##subsys##_set) \
	BTF_ID_FLAGS(func, kfunc) \
	LUNATIK_BTF_SET_END(bpf_lua##subsys##_set) \
	static const struct btf_kfunc_id_set bpf_lua##subsys##_kfunc_set = { \
		.owner = THIS_MODULE, \
		.set   = &bpf_lua##subsys##_set, \
	};

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#define LUNATIK_EBPF_KFUNC_INIT(subsys, prog_type) \
	return register_btf_kfunc_id_set(prog_type, &bpf_lua##subsys##_kfunc_set);
#else
#define LUNATIK_EBPF_KFUNC_INIT(subsys, prog_type) return 0;
#endif

#endif

