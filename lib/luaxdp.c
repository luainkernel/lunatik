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
#include "lunatik_bpf.h"

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

typedef struct luaxdp_ctx_s {
	struct xdp_buff  *xdp;
	void             *arg;
	size_t            arg__sz;
	int              *action;
	lunatik_object_t *packet;
	lunatik_object_t *argument;
} luaxdp_ctx_t;

LUNATIK_PRIVATECHECKER(luaxdp_ctx_check, luaxdp_ctx_t *,
	luaL_argcheck(L, private->xdp != NULL, ix, "ctx is not set");
);

/***
* Returns the packet data buffer for the current XDP context.
* @function packet
* @treturn data
*/
static int luaxdp_ctx_packet(lua_State *L)
{
	luaxdp_ctx_t *ctx = luaxdp_ctx_check(L, 1);
	lunatik_pushobject(L, ctx->packet);
	return 1;
}

/***
* Returns the argument data buffer passed from eBPF.
* @function argument
* @treturn data
*/
static int luaxdp_ctx_arg(lua_State *L)
{
	luaxdp_ctx_t *ctx = luaxdp_ctx_check(L, 1);
	lunatik_pushobject(L, ctx->argument);
	return 1;
}

/***
* Sets the XDP verdict action for this packet.
* @function set_action
* @tparam integer action XDP action constant (e.g. XDP_PASS, XDP_DROP, ...)
*/
static int luaxdp_set_action(lua_State *L)
{
	luaxdp_ctx_t *ctx = luaxdp_ctx_check(L, 1);
	*ctx->action = luaL_checkinteger(L, 2);
	return 0;
}

static const luaL_Reg luaxdp_ctx_mt[] = {
	{"__gc",        lunatik_deleteobject},
	{"packet",      luaxdp_ctx_packet},
	{"argument",    luaxdp_ctx_arg},
	{"set_action",  luaxdp_set_action},
	{NULL, NULL}
};

static void luaxdp_ctx_release(void *private)
{
	luaxdp_ctx_t *lctx = (luaxdp_ctx_t *)private;
	if (lctx->packet)
		luadata_close(lctx->packet);
	if (lctx->argument)
		luadata_close(lctx->argument);
}

LUNATIK_OPENER(ctx);
static const lunatik_class_t luaxdp_ctx_class = {
	.name    = "xdp.ctx",
	.methods = luaxdp_ctx_mt,
	.release = luaxdp_ctx_release,
	.opener  = luaopen_ctx,
	.opt     = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

static int luaxdp_push_ctx(lua_State *L, void *raw_ctx)
{
	luaxdp_ctx_t *ctx = (luaxdp_ctx_t *)raw_ctx;

	lunatik_require(L, &luaxdp_ctx_class);
	lunatik_object_t *object = lunatik_newobject(L, &luaxdp_ctx_class, sizeof(luaxdp_ctx_t), LUNATIK_OPT_NONE);
	luaxdp_ctx_t *lctx = (luaxdp_ctx_t *)object->private;
	lctx->xdp     = ctx->xdp;
	lctx->arg     = ctx->arg;
	lctx->arg__sz = ctx->arg__sz;
	lctx->action  = ctx->action;

	lctx->packet = luadata_new(L, LUNATIK_OPT_SINGLE);
	lunatik_getobject(lctx->packet);
	lunatik_register(L, -1, lctx->packet);
	lua_pop(L, 1);

	lctx->argument = luadata_new(L, LUNATIK_OPT_SINGLE);
	lunatik_getobject(lctx->argument);
	lunatik_register(L, -1, lctx->argument);
	lua_pop(L, 1);

	return 1;
}

static int luaxdp_callback(lua_State *L)
{
	luaxdp_ctx_t *ctx = (luaxdp_ctx_t *)lunatik_checkprivate(L, 1, &luaxdp_ctx_class);

	luadata_reset(ctx->packet,   ctx->xdp->data, ctx->xdp->data_end - ctx->xdp->data, LUADATA_OPT_KEEP);
	luadata_reset(ctx->argument, ctx->arg, ctx->arg__sz, LUADATA_OPT_KEEP);

	lua_pushvalue(L, lua_upvalueindex(1)); /* user callback */
	lua_pushvalue(L, 1);                   /* ctx userdata */

	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		luadata_clear(ctx->packet);
		luadata_clear(ctx->argument);
		return lua_error(L);
	}

	luadata_clear(ctx->packet);
	luadata_clear(ctx->argument);
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
	lunatik_object_t *runtime;
	int action = XDP_PASS;
	luaxdp_ctx_t ctx = {
		.xdp     = (struct xdp_buff *)xdp_ctx,
		.arg     = arg,
		.arg__sz = arg__sz,
		.action  = &action,
	};
	size_t keylen = key__sz - 1;

	if (unlikely(luaxdp_checkruntimes() != 0)) {
		pr_err("couldn't find _ENV.runtimes\n");
		return XDP_PASS;
	}

	key[keylen] = '\0';
	if ((runtime = luarcu_getobject(luaxdp_runtimes, key, keylen)) == NULL) {
		pr_err("couldn't find runtime '%.*s'\n", (int)keylen, key);
		return XDP_PASS;
	}
	lunatik_bpf_run(runtime, key, keylen, luaxdp_callback, luaxdp_push_ctx, &ctx);
	lunatik_putobject(runtime);
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
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
* 1. `ctx` (xdp.ctx userdata): A context object used to inspect the packet
*    and control the XDP verdict via `ctx:set_action()`.
*
*   The callback **must not return a value**. If no action is set, the default
*   is `XDP_PASS`.
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   local xdp    = require("xdp")
*   local action = require("linux.xdp")
*
*   xdp.attach(function(ctx)
*     local pkt = ctx:packet()
*     ctx:set_action(action.PASS)
*   end)
* @see data
* @within xdp
*/
static int luaxdp_attach(lua_State *L)
{
	lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lua_pushcclosure(L, luaxdp_callback, 1);
	lunatik_register(L, -1, luaxdp_callback);
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

LUNATIK_CLASSES(xdp, &luaxdp_ctx_class);
LUNATIK_NEWLIB(xdp, luaxdp_lib, luaxdp_classes);

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

