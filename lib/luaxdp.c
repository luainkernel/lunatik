/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/version.h>
#include <linux/bpf.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <lunatik.h>

#include "luarcu.h"
#include "luadata.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <net/xdp.h>

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0))
__bpf_kfunc_start_defs();
#else
__diag_push();
__diag_ignore_all("-Wmissing-prototypes",
                  "Global kfuncs as their definitions will be in BTF");
#endif

static inline lunatik_object_t *luaxdp_pushdata(lua_State *L, int upvalue, void *ptr, size_t size)
{
	lunatik_object_t *data;

	lua_pushvalue(L, lua_upvalueindex(upvalue));
	data = (lunatik_object_t *)lunatik_toobject(L, -1);
	luadata_reset(data, ptr, size, LUADATA_OPT_KEEP);
	return data;
}

static int luaxdp_callback(lua_State *L)
{
	lunatik_object_t *buffer, *argument;
	struct xdp_buff *ctx = (struct xdp_buff *)lua_touserdata(L, 1);
	void *arg = lua_touserdata(L, 2);
	size_t arg__sz = (size_t)lua_tointeger(L, 3);

	lua_pushvalue(L, lua_upvalueindex(1)); /* callback */
	buffer = luaxdp_pushdata(L, 2, ctx->data, ctx->data_end - ctx->data);
	argument = luaxdp_pushdata(L, 3, arg, arg__sz);

	if (lua_pcall(L, 2, 1, 0) != LUA_OK) {
		luadata_clear(buffer);
		luadata_clear(argument);
		return lua_error(L);
	}

	luadata_clear(buffer);
	luadata_clear(argument);
	return 1;
}

static int luaxdp_handler(lua_State *L, struct xdp_buff *ctx, void *arg, size_t arg__sz)
{
	int action = -1;
	int status;

	if (lunatik_getregistry(L, luaxdp_callback) != LUA_TFUNCTION) {
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

__bpf_kfunc int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *xdp_ctx, void *arg, size_t arg__sz)
{
	lunatik_object_t *runtime;
	struct xdp_buff *ctx = (struct xdp_buff *)xdp_ctx;
	int action = -1;
	size_t keylen = key__sz - 1;

	key[keylen] = '\0';
	if ((runtime = luarcu_gettable(lunatik_runtimes, key, keylen)) == NULL) {
		pr_err("couldn't find runtime '%s'\n", key);
		goto out;
	}

	lunatik_run(runtime, luaxdp_handler, action, ctx, arg, arg__sz);
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
BTF_KFUNCS_START(bpf_luaxdp_set)
BTF_ID_FLAGS(func, bpf_luaxdp_run)
BTF_KFUNCS_END(bpf_luaxdp_set)
#else
BTF_SET8_START(bpf_luaxdp_set)
BTF_ID_FLAGS(func, bpf_luaxdp_run)
BTF_SET8_END(bpf_luaxdp_set)
#endif

static const struct btf_kfunc_id_set bpf_luaxdp_kfunc_set = {
	.owner = THIS_MODULE,
	.set   = &bpf_luaxdp_set,
};

#define luaxdp_setcallback(L, i)	(lunatik_setregistry((L), (i), luaxdp_callback))

static inline void luaxdp_newdata(lua_State *L)
{
	lunatik_object_t *data = lunatik_checknull(L, luadata_new(NULL, 0, false, LUADATA_OPT_NONE));
	lunatik_cloneobject(L, data);
}

static int luaxdp_detach(lua_State *L)
{
	lua_pushnil(L);
	luaxdp_setcallback(L, 1);
	return 0;
}

static int luaxdp_attach(lua_State *L)
{
	lunatik_checkruntime(L, false);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lunatik_requiref(L, data);
	luaxdp_newdata(L); /* buffer */
	luaxdp_newdata(L); /* argument */

	lua_pushcclosure(L, luaxdp_callback, 3);
	luaxdp_setcallback(L, -1);
	return 0;
}
#endif

static const luaL_Reg luaxdp_lib[] = {
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	{"attach", luaxdp_attach},
	{"detach", luaxdp_detach},
#endif
	{NULL, NULL}
};

static const lunatik_reg_t luaxdp_action[] = {
	{"ABORTED", XDP_ABORTED},
	{"DROP", XDP_DROP},
	{"PASS", XDP_PASS},
	{"TX", XDP_TX},
	{"REDIRECT", XDP_REDIRECT},
	{NULL, 0}
};

static const lunatik_namespace_t luaxdp_flags[] = {
	{"action", luaxdp_action},
	{NULL, NULL}
};

LUNATIK_NEWLIB(xdp, luaxdp_lib, NULL, luaxdp_flags);

static int __init luaxdp_init(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	return register_btf_kfunc_id_set(BPF_PROG_TYPE_XDP, &bpf_luaxdp_kfunc_set);
#else
	return 0;
#endif
}

static void __exit luaxdp_exit(void)
{
}

module_init(luaxdp_init);
module_exit(luaxdp_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

