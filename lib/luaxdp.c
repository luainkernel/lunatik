/*
* SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* eXpress Data Path (XDP) integration.
* This library allows Lua scripts to interact with the kernel's XDP subsystem.
* It enables XDP/eBPF programs to call Lua functions for packet processing,
* providing a flexible way to implement custom packet handling logic in Lua
* at a very early stage in the network stack.
*
* The primary mechanism involves an XDP program calling the `bpf_luaxdp_run`
* kfunc, which in turn invokes a Lua callback function previously registered
* using `xdp.attach()`.
* @module xdp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bpf.h>

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

static lunatik_object_t *luaxdp_runtimes = NULL;

typedef struct luaxdp_ctx {
	lunatik_object_t	*buffer;
	lunatik_object_t	*argument;
	struct xdp_buff		*xdp;
	void				*arg;
	size_t				arg__sz;
	int					action;
} luaxdp_ctx_t;

static int luaxdp_packet(lua_State *L)
{
	luaxdp_ctx_t *ctx = *(luaxdp_ctx_t **)lua_touserdata(L, 1);

	luadata_reset(ctx->buffer, ctx->xdp->data, ctx->xdp->data_end - ctx->xdp->data, LUADATA_OPT_KEEP);
	lunatik_pushobject(L, ctx->buffer);
	return 1;
}

static int luaxdp_argument(lua_State *L)
{
	luaxdp_ctx_t *ctx = *(luaxdp_ctx_t **)lua_touserdata(L, 1);

	luadata_reset(ctx->argument, ctx->arg, ctx->arg__sz, LUADATA_OPT_KEEP);
	lunatik_pushobject(L, ctx->argument);
	return 1;
}

static int luaxdp_set_action(lua_State *L)
{
	luaxdp_ctx_t *ctx = *(luaxdp_ctx_t **)lua_touserdata(L, 1);

	ctx->action = (int)luaL_checkinteger(L, 2);
	return 0;
}

static const luaL_Reg luaxdp_ctx_methods[] = {
	{"packet",		luaxdp_packet},
	{"argument",	luaxdp_argument},
	{"set_action",	luaxdp_set_action},
	{NULL, NULL}
};

static void luaxdp_ctx_register(lua_State *L)
{
	luaL_newmetatable(L, "luaxdp.ctx");

	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	luaL_setfuncs(L, luaxdp_ctx_methods, 0);

	lua_pop(L, 1);
}

static int luaxdp_callback(lua_State *L, void *arg)
{
	luaxdp_ctx_t *ctx = (luaxdp_ctx_t *)arg;

	if (lunatik_getregistry(L, luaxdp_callback) != LUA_TFUNCTION) {
		pr_err("callback not found");
		return -1;
	}
	luaxdp_ctx_t **ud = lua_newuserdata(L, sizeof(*ud));
	*ud = ctx;
	luaL_setmetatable(L, "luaxdp.ctx");

	if (lua_pcall(L, 1, 0, 0) != LUA_OK)
		return lua_error(L);

	return 0;
}

static inline int luaxdp_checkruntimes(void)
{
	const char *key = "runtimes";
	if (luaxdp_runtimes == NULL &&
	   (luaxdp_runtimes = luarcu_getobject(lunatik_env, key, sizeof(key))) == NULL)
		return -1;
	return 0;
}

__bpf_kfunc int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *xdp_ctx, void *arg, size_t arg__sz)
{
	struct luaxdp_ctx ctx = {
		.xdp     = (struct xdp_buff *)xdp_ctx,
		.arg     = arg,
		.arg__sz = arg__sz,
		.action  = XDP_PASS,
	};
	lunatik_object_t *runtime;
	size_t keylen = key__sz - 1;

	if (unlikely(luaxdp_checkruntimes() != 0))
		return XDP_PASS;

	key[keylen] = '\0';
	if ((runtime = luarcu_getobject(luaxdp_runtimes, key, keylen)) == NULL)
		return XDP_PASS;

	lunatik_bpf_run(runtime, luaxdp_callback, &ctx);
	lunatik_putobject(runtime);
	return ctx.action;
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

/***
* Unregisters the Lua callback function associated with the current Lunatik runtime.
* After calling this, `bpf_luaxdp_run` calls targeting this runtime will no longer
* invoke a Lua function (they will likely return an error or default action).
* @function detach
* @treturn nil
* @usage
*   xdp.detach()
* @within xdp
*/
static int luaxdp_detach(lua_State *L)
{
	lunatik_unregister(L, luaxdp_callback);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by an XDP/eBPF program.
* When an XDP program calls the `bpf_luaxdp_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime invoking this function must be non-sleepable.
*
* The `bpf_luaxdp_run` kfunc is called from an eBPF program with the following signature:
* `int bpf_luaxdp_run(char *key, size_t key_sz, struct xdp_md *xdp_ctx, void *arg, size_t arg_sz)`
*
* - `key`: A string identifying the Lunatik runtime (e.g., the script name like "examples/filter/sni").
*   This key is used to look up the runtime in Lunatik's internal table of active runtimes.
* - `key_sz`: Length of the key string (including the null terminator).
* - `xdp_ctx`: The XDP metadata context (`struct xdp_md *`).
* - `arg`: A pointer to arbitrary data passed from eBPF to Lua.
* - `arg_sz`: The size of the `arg` data.
*
* @function attach
* @tparam function callback Lua function to call. It receives two arguments:
*
* 1. `buffer` (data): A `data` object representing the network packet buffer (`xdp_md`).
*    The `data` object points to `xdp_ctx->data` and its size is `xdp_ctx->data_end - xdp_ctx->data`.
* 2. `argument` (data): A `data` object representing the `arg` passed from the eBPF program.
*    Its size is `arg_sz`.
*
*   The callback function should return an integer verdict, typically one of the values
*   from `linux.xdp` (e.g., `action.PASS`, `action.DROP`).
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   -- Lua script (e.g., "my_xdp_handler.lua" which is run via `lunatik run my_xdp_handler.lua`)
*   local xdp = require("xdp")
*   local action = require("linux.xdp")
*
*   local function my_packet_processor(packet_buffer, custom_arg)
*     print("Packet received, size:", #packet_buffer)
*     return action.PASS
*   end
*   xdp.attach(my_packet_processor)
*
*   -- In eBPF C code, to call the above Lua function:
*   -- char rt_key[] = "my_xdp_handler.lua"; // Key matches the script name
*   -- int verdict = bpf_luaxdp_run(rt_key, sizeof(rt_key), ctx, NULL, 0);
* @see data
* @within xdp
*/
static int luaxdp_attach(lua_State *L)
{
	lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION);

	lua_pushvalue(L, 1);

	lua_pushcclosure(L, luaxdp_callback, 1);
	lunatik_register(L, -1, NULL);

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

int luaopen_xdp(lua_State *L)
{
	luaL_newlib(L, luaxdp_lib);

	luaxdp_ctx_register(L);

	return 1;
}
EXPORT_SYMBOL_GPL(luaopen_xdp);

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
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	if (luaxdp_runtimes != NULL)
		lunatik_putobject(luaxdp_runtimes);
#endif
}

module_init(luaxdp_init);
module_exit(luaxdp_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

