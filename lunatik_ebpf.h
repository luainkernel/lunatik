/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef LUNATIK_EBPF_H
#define LUNATIK_EBPF_H

#include "lib/luarcu.h"

static inline int lunatik_ebpf_checkruntimes(lunatik_object_t **runtimes, lunatik_object_t **percpu)
{
	static const char runtimes_key[] = "runtimes";
	static const char percpu_key[] = "percpu";
	if (*runtimes == NULL)
		*runtimes = luarcu_getobject(lunatik_env, runtimes_key, sizeof(runtimes_key) - 1);
	if (*percpu == NULL)
		*percpu = luarcu_getobject(lunatik_env, percpu_key, sizeof(percpu_key) - 1);
	return *runtimes && *percpu ? 0 : -1;
}

static inline lunatik_object_t *lunatik_ebpf_lookupruntime(lunatik_object_t **runtimes, lunatik_object_t **percpu, char *key, size_t key_sz, int cpuid)
{
	lunatik_object_t *runtime = NULL;
	size_t keylen = key_sz - 1;
	key[keylen] = '\0';
	if (unlikely(lunatik_ebpf_checkruntimes(runtimes, percpu) != 0)) {
		pr_err_ratelimited("couldn't find _ENV.runtimes or _ENV.percpu\n");
		return NULL;
	}
	runtime = luarcu_getobject(*runtimes, key, keylen);
	if (!runtime) {
		char cpu_key[LUARCU_MAXKEY];
		size_t cpulen;
		cpulen = scnprintf(cpu_key, sizeof(cpu_key), "%s:%d", key, cpuid);
		runtime = luarcu_getobject(*percpu, cpu_key, cpulen);
	}
	return runtime;
}

static inline void *lunatik_ebpf_getctx(lua_State *L, char *env_key)
{
	lunatik_object_t *obj;
	if (lunatik_getregistry(L, env_key) != LUA_TUSERDATA) {
		lua_pop(L, 1);
		pr_err("couldn't find the context object\n");
		return NULL;
	}
	obj = (lunatik_object_t *)lunatik_toobject(L, -1);
	return obj->private;
}

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

