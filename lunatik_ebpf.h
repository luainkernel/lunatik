/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef LUNATIK_EBPF_H
#define LUNATIK_EBPF_H

#include "lib/luarcu.h"

static char lunatik_ebpf_env_key;
static lunatik_object_t *lunatik_ebpf_runtimes = NULL;
static lunatik_object_t *lunatik_ebpf_percpu = NULL;

/* a zero size is allowed by the verifier and would underflow the length */
static inline int lunatik_ebpf_checkkey(char *key, size_t key_sz, size_t *keylen)
{
	if (unlikely(key_sz == 0))
		return -1;
	*keylen = key_sz - 1;
	key[*keylen] = '\0';
	return 0;
}

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

static inline lunatik_object_t *lunatik_ebpf_lookupruntime(lunatik_object_t **runtimes,
		lunatik_object_t **percpu, char *key, size_t key_sz, int cpuid)
{
	lunatik_object_t *runtime = NULL;
	size_t keylen;

	if (lunatik_ebpf_checkkey(key, key_sz, &keylen) != 0)
		return NULL;
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

/* on success the context userdata stays on the stack, ready to be passed to the callback */
static inline void *lunatik_ebpf_getctx(lua_State *L)
{
	lunatik_object_t *obj;
	if (lunatik_getregistry(L, &lunatik_ebpf_env_key) != LUA_TUSERDATA) {
		lua_pop(L, 1);
		pr_err_ratelimited("couldn't find the context object\n");
		return NULL;
	}
	obj = (lunatik_object_t *)lunatik_toobject(L, -1);
	return obj->private;
}

/* invokes the Lua callback referenced by 'callback_ref', consuming the
 * context userdata that lunatik_ebpf_getctx() left on top of the stack */
static inline int lunatik_ebpf_invoke(lua_State *L, int callback_ref)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);
	if (!lua_isfunction(L, -1)) {
		pr_err_ratelimited("callback_ref is not a function\n");
		lua_pop(L, 2);
		return -1;
	}

	lua_insert(L, -2);
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		pr_err_ratelimited("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		return -1;
	}
	return 0;
}

/* references the Lua function at stack index 1 as the callback and binds its
 * lifetime to 'env_key' (the ctx object must already be on top of the stack) */
static inline void lunatik_ebpf_attach(lua_State *L, int *callback_ref)
{
	lua_pushvalue(L, 1);
	*callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	lunatik_register(L, -1, &lunatik_ebpf_env_key);
	lua_pop(L, 1);
}

/* the caller still unregisters any binding specific sub-objects */
static inline void lunatik_ebpf_detach(lua_State *L, int *callback_ref)
{
	luaL_unref(L, LUA_REGISTRYINDEX, *callback_ref);
	*callback_ref = LUA_NOREF;
	lunatik_unregister(L, &lunatik_ebpf_env_key);
	lua_pop(L, 1);
}

/* looks up the runtime for 'key'/'key_sz', runs 'handler' with 'ctxp' on it,
 * and releases the runtime; a no-op if no matching runtime is found */
#define LUNATIK_EBPF_RUN(subsys, key, key_sz, handler, ctxp) \
do { \
	lunatik_object_t *__runtime = lunatik_ebpf_lookupruntime(&lunatik_ebpf_runtimes, \
			&lunatik_ebpf_percpu, (key), (key_sz), raw_smp_processor_id()); \
	if (__runtime != NULL) { \
		int __ret; \
		lunatik_run(__runtime, (handler), __ret, (ctxp)); \
		lunatik_putobject(__runtime); \
	} \
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
#define LUNATIK_EBPF_NEWLIB(subsys, lib, class) \
	LUNATIK_CLASSES(subsys, class); \
	LUNATIK_NEWLIB(subsys, lib, lua##subsys##_classes)

#define LUNATIK_EBPF_KFUNC_INIT(subsys, prog_type) \
static int __init lua##subsys##_init(void) \
{ \
	return register_btf_kfunc_id_set(prog_type, &bpf_lua##subsys##_kfunc_set); \
}
#define LUNATIK_EBPF_EXIT(subsys) \
static void __exit lua##subsys##_exit(void) \
{ \
	if (lunatik_ebpf_runtimes != NULL) \
		lunatik_putobject(lunatik_ebpf_runtimes); \
	if (lunatik_ebpf_percpu != NULL) \
		lunatik_putobject(lunatik_ebpf_percpu); \
}
#else
#define LUNATIK_EBPF_NEWLIB(subsys, lib, class) \
	static const lunatik_class_t *lua##subsys##_classes[] = { NULL }; \
	LUNATIK_NEWLIB(subsys, lib, lua##subsys##_classes)

#define LUNATIK_EBPF_KFUNC_INIT(subsys, prog_type) \
static int __init lua##subsys##_init(void) \
{ \
	return 0; \
}
#define LUNATIK_EBPF_EXIT(subsys) \
static void __exit lua##subsys##_exit(void) \
{ \
}
#endif

#endif

