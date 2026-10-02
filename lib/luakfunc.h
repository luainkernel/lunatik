/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luakfunc_h
#define luakfunc_h

#include "luarcu.h"

static const char luakfunc_env_key;
static lunatik_object_t *luakfunc_runtimes = NULL;

static inline lunatik_object_t *luakfunc_getruntimes(void)
{
	static const char runtimes_key[] = "runtimes";
	lunatik_object_t *runtimes = READ_ONCE(luakfunc_runtimes);
	lunatik_object_t *env = READ_ONCE(lunatik_env);

	if (runtimes != NULL || env == NULL)
		return runtimes;
	runtimes = luarcu_getobject(env, runtimes_key, sizeof(runtimes_key) - 1);
	if (runtimes != NULL && cmpxchg(&luakfunc_runtimes, NULL, runtimes) != NULL)
		lunatik_putobject(runtimes); /* another CPU cached the table first */
	return READ_ONCE(luakfunc_runtimes);
}

static inline lunatik_object_t *luakfunc_lookupruntime(char *key, size_t key_sz)
{
	if (unlikely(key_sz == 0)) /* the verifier allows a zero size, which would underflow the length */
		return NULL;
	size_t keylen = key_sz - 1;
	key[keylen] = '\0';

	lunatik_object_t *runtimes = luakfunc_getruntimes();
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

static inline void *luakfunc_findctx(lua_State *L)
{
	if (lunatik_getregistry(L, &luakfunc_env_key) != LUA_TUSERDATA) {
		lua_pop(L, 1);
		return NULL;
	}
	return lunatik_toobject(L, -1)->private;
}

static inline void *luakfunc_getctx(lua_State *L)
{
	void *ctx = luakfunc_findctx(L);

	if (ctx == NULL)
		pr_err_ratelimited("no callback attached (cpu %d)\n", lunatik_getcpu(L));
	return ctx;
}

static inline int luakfunc_invoke(lua_State *L, int cb, int nresults)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, cb);
	lua_insert(L, -2);
	if (lua_pcall(L, 1, nresults, 0) != LUA_OK) {
		pr_err_ratelimited("%s\n", lunatik_errmsg(L));
		lua_pop(L, 1);
		return -1;
	}
	return 0;
}

static inline int luakfunc_action(lua_State *L, int cb, lua_Integer min, lua_Integer max)
{
	if (luakfunc_invoke(L, cb, 1) != 0 || lua_isnil(L, -1))
		return -1;

	lua_Integer action = lua_tointeger(L, -1);
	if (lua_type(L, -1) == LUA_TNUMBER && action >= min && action <= max)
		return (int)action;

	pr_err_ratelimited("invalid action\n");
	return -1;
}

#define luakfunc_attach(L, obj, field, new_fn, ...)	\
do {								\
	obj->field = new_fn((L), ##__VA_ARGS__);		\
	lunatik_getobject(obj->field);				\
	lunatik_register((L), -1, obj->field);			\
	lua_pop((L), 1);					\
} while (0)

#define luakfunc_detach(L, obj, field)	lunatik_unregister((L), obj->field)

static inline void luakfunc_bind(lua_State *L, int ix, int *cb)
{
	lua_pushvalue(L, ix);
	*cb = luaL_ref(L, LUA_REGISTRYINDEX);

	lunatik_register(L, -1, &luakfunc_env_key);
	lua_pop(L, 1);
}

static inline void luakfunc_unbind(lua_State *L, int *cb)
{
	luaL_unref(L, LUA_REGISTRYINDEX, *cb);
	*cb = LUA_NOREF;
	lunatik_unregister(L, &luakfunc_env_key);
	lua_pop(L, 1);
}

#define LUAKFUNC_RUN(key, key_sz, handler, ret, ctxp) \
do { \
	lunatik_object_t *__runtime = luakfunc_lookupruntime((key), (key_sz)); \
	if (__runtime != NULL) { \
		int __ret; \
		lunatik_run(__runtime, (handler), __ret, (ctxp)); \
		lunatik_putobject(__runtime); \
		(ret) = __ret < 0 ? -1 : __ret; /* lunatik_run's -ENXIO or -EDEADLK included */ \
	} \
} while (0)

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0))
#define LUAKFUNC_START() __bpf_kfunc_start_defs()
#define LUAKFUNC_END()   __bpf_kfunc_end_defs()
#else
#define LUAKFUNC_START() \
	__diag_push(); \
	__diag_ignore_all("-Wmissing-prototypes", \
			"Global kfuncs as their definitions will be in BTF")
#define LUAKFUNC_END()   __diag_pop()
#endif

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 9, 0))
#define LUAKFUNC_BTF_SET_START(name) BTF_KFUNCS_START(name)
#define LUAKFUNC_BTF_SET_END(name)   BTF_KFUNCS_END(name)
#else
#define LUAKFUNC_BTF_SET_START(name) BTF_SET8_START(name)
#define LUAKFUNC_BTF_SET_END(name)   BTF_SET8_END(name)
#endif

#define LUAKFUNC_DEFINE_SET(subsys, kfunc) \
	LUAKFUNC_BTF_SET_START(bpf_lua##subsys##_set) \
	BTF_ID_FLAGS(func, kfunc) \
	LUAKFUNC_BTF_SET_END(bpf_lua##subsys##_set) \
	static const struct btf_kfunc_id_set bpf_lua##subsys##_kfunc_set = { \
		.owner = THIS_MODULE, \
		.set   = &bpf_lua##subsys##_set, \
	};

#define LUAKFUNC_NEWLIB(subsys, lib, class) \
	LUNATIK_CLASSES(subsys, class); \
	LUNATIK_NEWLIB(subsys, lib, lua##subsys##_classes)

#define LUAKFUNC_INIT(subsys, prog_type) \
static int __init lua##subsys##_init(void) \
{ \
	return register_btf_kfunc_id_set(prog_type, &bpf_lua##subsys##_kfunc_set); \
}
#define LUAKFUNC_EXIT(subsys) \
static void __exit lua##subsys##_exit(void) \
{ \
	if (luakfunc_runtimes != NULL) \
		lunatik_putobject(luakfunc_runtimes); \
}

#endif

