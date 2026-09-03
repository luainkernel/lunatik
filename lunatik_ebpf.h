/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef LUNATIK_EBPF_H
#define LUNATIK_EBPF_H

#include "lib/luarcu.h"

static char lunatik_ebpf_env_key;
static lunatik_object_t *lunatik_ebpf_runtimes = NULL;

static inline lunatik_object_t *lunatik_ebpf_getruntimes(void)
{
	static const char runtimes_key[] = "runtimes";
	if (lunatik_ebpf_runtimes == NULL)
		lunatik_ebpf_runtimes = luarcu_getobject(lunatik_env, runtimes_key, sizeof(runtimes_key) - 1);
	return lunatik_ebpf_runtimes;
}

static inline lunatik_object_t *lunatik_ebpf_lookupruntime(char *key, size_t key_sz)
{
	if (unlikely(key_sz == 0)) /* the verifier allows a zero size, which would underflow the length */
		return NULL;
	size_t keylen = key_sz - 1;
	key[keylen] = '\0';

	lunatik_object_t *runtimes = lunatik_ebpf_getruntimes();
	if (unlikely(runtimes == NULL)) {
		pr_err_ratelimited("couldn't find _ENV.runtimes\n");
		return NULL;
	}
	lunatik_object_t *runtime = luarcu_getobject(runtimes, key, keylen);
	if (runtime == NULL || likely(lunatik_isirq(runtime->opt)))
		return runtime;

	pr_err_ratelimited("'%s' is a process-context runtime, not dispatched\n", key);
	lunatik_putobject(runtime);
	return NULL;
}

static inline void *lunatik_ebpf_getctx(lua_State *L)
{
	if (lunatik_getregistry(L, &lunatik_ebpf_env_key) != LUA_TUSERDATA) {
		lua_pop(L, 1);
		pr_err_ratelimited("no callback attached (cpu %d)\n", lunatik_getcpu(L));
		return NULL;
	}
	return lunatik_toobject(L, -1)->private;
}

static inline int lunatik_ebpf_invoke(lua_State *L, int cb)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, cb);
	lua_insert(L, -2);
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		pr_err_ratelimited("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		return -1;
	}
	return 0;
}

#define lunatik_ebpf_attach(L, obj, field, new_fn, ...)	\
do {								\
	obj->field = new_fn((L), ##__VA_ARGS__);		\
	lunatik_getobject(obj->field);				\
	lunatik_register((L), -1, obj->field);			\
	lua_pop((L), 1);					\
} while (0)

#define lunatik_ebpf_detach(L, obj, field)	lunatik_unregister((L), obj->field)

static inline void lunatik_ebpf_bind(lua_State *L, int ix, int *cb)
{
	lua_pushvalue(L, ix);
	*cb = luaL_ref(L, LUA_REGISTRYINDEX);

	lunatik_register(L, -1, &lunatik_ebpf_env_key);
	lua_pop(L, 1);
}

static inline void lunatik_ebpf_unbind(lua_State *L, int *cb)
{
	luaL_unref(L, LUA_REGISTRYINDEX, *cb);
	*cb = LUA_NOREF;
	lunatik_unregister(L, &lunatik_ebpf_env_key);
	lua_pop(L, 1);
}

#define LUNATIK_EBPF_RUN(key, key_sz, handler, ctxp) \
do { \
	lunatik_object_t *__runtime = lunatik_ebpf_lookupruntime((key), (key_sz)); \
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
#define LUNATIK_EBPF_BTF_SET_START(name) BTF_KFUNCS_START(name)
#define LUNATIK_EBPF_BTF_SET_END(name)   BTF_KFUNCS_END(name)
#else
#define LUNATIK_EBPF_BTF_SET_START(name) BTF_SET8_START(name)
#define LUNATIK_EBPF_BTF_SET_END(name)   BTF_SET8_END(name)
#endif

#define LUNATIK_EBPF_KFUNC_DEFINE_SET(subsys, kfunc) \
	LUNATIK_EBPF_BTF_SET_START(bpf_lua##subsys##_set) \
	BTF_ID_FLAGS(func, kfunc) \
	LUNATIK_EBPF_BTF_SET_END(bpf_lua##subsys##_set) \
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

