/*
* SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Traffic Controller (TC) integration.
* This library allows Lua scripts to interact with the kernel's TC subsystem.
* It enables TC/eBPF programs to call Lua functions for packet processing,
* providing a flexible way to implement custom packet handling logic in Lua
* at a very early stage in the network stack.
*
* The primary mechanism involves an TC program calling the `bpf_luatc_run`
* kfunc, which in turn invokes a Lua callback function previously registered
* using `tc.attach()`.
* @module tc
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bpf.h>

#include <lunatik.h>

#include "luarcu.h"
#include "luadata.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <linux/pkt_cls.h>

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0))
__bpf_kfunc_start_defs();
#else
__diag_push();
__diag_ignore_all("-Wmissing-prototypes",
                  "Global kfuncs as their definitions will be in BTF");
#endif

static lunatik_object_t *luatc_runtimes = NULL;

static inline lunatik_object_t *luatc_pushdata(lua_State *L, int upvalue, void *ptr, size_t size)
{
	lunatik_object_t *data;

	lua_pushvalue(L, lua_upvalueindex(upvalue));
	data = (lunatik_object_t *)lunatik_toobject(L, -1);
	luadata_reset(data, ptr, 0, size, LUADATA_OPT_KEEP);
	return data;
}

static int luatc_callback(lua_State *L)
{
	lunatik_object_t *buffer, *argument;
	struct __sk_buff *skb = (struct __sk_buff *)lua_touserdata(L, 1);
	void *arg = lua_touserdata(L, 2);
	size_t arg__sz = (size_t)lua_tointeger(L, 3);
	void *data = (void *)(long)skb->data;
	void *data_end = (void *)(long)skb->data_end;

	lua_pushvalue(L, lua_upvalueindex(1)); /* callback */
	buffer = luatc_pushdata(L, 2, data, data_end - data);
	argument = luatc_pushdata(L, 3, arg, arg__sz);

	if (lua_pcall(L, 2, 1, 0) != LUA_OK) {
		luadata_clear(buffer);
		luadata_clear(argument);
		return lua_error(L);
	}

	luadata_clear(buffer);
	luadata_clear(argument);
	return 1;
}

static int luatc_handler(lua_State *L, struct __sk_buff *ctx, void *arg, size_t arg__sz)
{
	int action = TC_ACT_UNSPEC;
	int status;

	if (lunatik_getregistry(L, luatc_callback) != LUA_TFUNCTION) {
		pr_err("couldn't find callback");
		goto out;
	}

	lua_pushlightuserdata(L, ctx);
	lua_pushlightuserdata(L, arg);
	lua_pushinteger(L, (lua_Integer)arg__sz);
	if ((status = lua_pcall(L, 3, 1, 0)) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		goto out;
	}

	action = lua_tointeger(L, -1);
out:
	return action;
}

static inline int luatc_checkruntimes(void)
{
	const char *key = "runtimes";
	if (luatc_runtimes == NULL &&
	   (luatc_runtimes = luarcu_gettable(lunatik_env, key, sizeof(key))) == NULL)
		return -1;
	return 0;
}

__bpf_kfunc int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *tc_ctx, void *arg, size_t arg__sz)
{
	lunatik_object_t *runtime;
	int action = TC_ACT_UNSPEC;
	size_t keylen = key__sz - 1;

	if (unlikely(luatc_checkruntimes() != 0)) {
		pr_err("couldn't find _ENV.runtimes\n");
		goto out;
	}

	key[keylen] = '\0';
	if ((runtime = luarcu_gettable(luatc_runtimes, key, keylen)) == NULL) {
		pr_err("couldn't find runtime '%s'\n", key);
		goto out;
	}

	lunatik_run(runtime, luatc_handler, action, tc_ctx, arg, arg__sz);
	lunatik_putobject(runtime);
out:
	return action;
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0))
__bpf_kfunc_end_defs();
#else
__diag_pop();
#endif

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 9, 0))
BTF_KFUNCS_START(bpf_luatc_set)
BTF_ID_FLAGS(func, bpf_luatc_run)
BTF_KFUNCS_END(bpf_luatc_set)
#else
BTF_SET8_START(bpf_luatc_set)
BTF_ID_FLAGS(func, bpf_luatc_run)
BTF_SET8_END(bpf_luatc_set)
#endif

static const struct btf_kfunc_id_set bpf_luatc_kfunc_set = {
	.owner = THIS_MODULE,
	.set   = &bpf_luatc_set,
};

static int luatc_detach(lua_State *L)
{
	lunatik_unregister(L, luatc_callback);
	return 0;
}

static int luatc_attach(lua_State *L)
{
	lunatik_checkruntime(L, false);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	luadata_new(L); /* buffer */
	luadata_new(L); /* argument */

	lua_pushcclosure(L, luatc_callback, 3);
	lunatik_register(L, -1, luatc_callback);
	return 0;
}
#endif

static const luaL_Reg luatc_lib[] = {
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	{"attach", luatc_attach},
	{"detach", luatc_detach},
#endif
	{NULL, NULL}
};

static const lunatik_reg_t luatc_action[] = {
	{ "UNSPEC",   TC_ACT_UNSPEC },
	{ "OK",       TC_ACT_OK },
	{ "SHOT",     TC_ACT_SHOT },
	{ "REDIRECT", TC_ACT_REDIRECT },
	{ "STOLEN",   TC_ACT_STOLEN },
	{ "QUEUED",   TC_ACT_QUEUED },
	{ "REPEAT",   TC_ACT_REPEAT },
	{ NULL, 0 }
};

static const lunatik_namespace_t luatc_flags[] = {
	{"action", luatc_action},
	{NULL, NULL}
};

LUNATIK_NEWLIB(tc, luatc_lib, NULL, luatc_flags);

static int __init luatc_init(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	return register_btf_kfunc_id_set(BPF_PROG_TYPE_SCHED_CLS, &bpf_luatc_kfunc_set);
#else
	return 0;
#endif
}

static void __exit luatc_exit(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	if (luatc_runtimes != NULL)
		lunatik_putobject(luatc_runtimes);
#endif
}

module_init(luatc_init);
module_exit(luatc_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>");

