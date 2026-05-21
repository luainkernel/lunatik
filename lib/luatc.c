/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux Traffic Controller (TC) integration.
* This library allows Lua scripts to interact with the kernel's TC subsystem.
* It enables TC/eBPF programs to call Lua functions for packet processing,
* traffic shaping, filtering, and policy enforcement, providing a flexible
* way to implement custom networking logic in Lua at the ingress and egress
* layers of network stack.
*
* The primary mechanism involves an TC program calling the `bpf_luatc_run`
* kfunc, which in turn invokes a Lua callback function previously registered
* using `tc.attach()`.
* @module tc
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bpf.h>

#include <lunatik.h>
#include <lunatik_ebpf.h>

#include "luarcu.h"
#include "luadata.h"
#include "luaskb.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <net/pkt_cls.h>

LUNATIK_EBPF_START();

static char luatc_env_key;

static lunatik_object_t *luatc_runtimes = NULL;

typedef struct luatc_ctx_s {
	struct __sk_buff *skb;
	void             *arg;
	size_t           arg__sz;
	int              *action;
	lunatik_object_t *argument;
	lunatik_object_t *skb_obj;
	int              callback_ref;
} luatc_ctx_t;

LUNATIK_PRIVATECHECKER(luatc_ctx_check, luatc_ctx_t *,
	luaL_argcheck(L, private->skb != NULL, ix, "ctx is not set");
);

/***
* Returns the packet data buffer for the current XDP context.
* @function skb
* @treturn data
*/
static int luatc_skb(lua_State *L)
{
	luatc_ctx_t *ctx = luatc_ctx_check(L, 1);
	lunatik_getregistry(L, ctx->skb_obj);
	return 1;
}

/***
* Returns the argument data buffer passed from eBPF.
* @function argument
* @treturn data
*/
static int luatc_arg(lua_State *L)
{
	luatc_ctx_t *ctx = luatc_ctx_check(L, 1);
    lunatik_getregistry(L, ctx->argument);
	return 1;
}

/***
* Sets the TC verdict action for this packet.
* @function set_action
* @tparam integer action TC action constant (e.g. XDP_PASS, XDP_DROP, ...)
*/
static int luatc_action(lua_State *L)
{
	luatc_ctx_t *ctx = luatc_ctx_check(L, 1);
	*ctx->action = luaL_checkinteger(L, 2);
	return 0;
}

static const luaL_Reg luatc_mt[] = {
	{"__gc",		lunatik_deleteobject},
	{"skb",			luatc_skb},
	{"argument",	luatc_arg},
	{"action",		luatc_action},
	{NULL, NULL}
};

static void luatc_release(void *private)
{
	luatc_ctx_t *lctx = (luatc_ctx_t *)private;
	if (lctx->skb_obj)
		luaskb_clear(lctx->skb_obj);
	if (lctx->argument)
		luadata_close(lctx->argument);
}

LUNATIK_OPENER(tc);
static const lunatik_class_t luatc_class = {
	.name    = "tc.ctx",
	.methods = luatc_mt,
	.release = luatc_release,
	.opener  = luaopen_tc,
	.opt     = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

static void luatc_handler_cleanup(luatc_ctx_t *lctx)
{
	luaskb_t *lskb = (luaskb_t *)lctx->skb_obj->private;
	luadata_clear(lctx->argument);
	lskb->skb = NULL;
	lctx->action = NULL;
}

static int luatc_handler(lua_State *L, luatc_ctx_t *ctx)
{
	luatc_ctx_t *lctx;
	lunatik_bpf_get_env(L, &luatc_env_key, lctx);
	luaskb_t *lskb = (luaskb_t *)lctx->skb_obj->private;

	lskb->skb = (struct sk_buff *)ctx->skb;

	lctx->skb     = ctx->skb;
	lctx->arg     = ctx->arg;
	lctx->arg__sz = ctx->arg__sz;
	lctx->action  = ctx->action;

	luadata_reset(lctx->argument, lctx->arg, lctx->arg__sz, LUADATA_OPT_KEEP);

	lua_rawgeti(L, LUA_REGISTRYINDEX, lctx->callback_ref);
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 2);
		pr_err("callback_ref is not a function\n");
		luatc_handler_cleanup(lctx);
		return -1;
	}

	lua_insert(L, -2);
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		luatc_handler_cleanup(lctx);
		return -1;
	}

	luatc_handler_cleanup(lctx);
	return 0;
}

__bpf_kfunc int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *skb, void *arg, size_t arg__sz)
{
	int action = -1;

	lunatik_object_t *runtime = lunatik_ebpf_lookup(luatc_runtimes, key, key__sz);
	if (runtime == NULL)
		goto out;

	luatc_ctx_t ctx = {
		.skb     = skb,
		.arg     = arg,
		.arg__sz = arg__sz,
		.action  = &action,
	};

	lunatik_run(runtime, luatc_handler, action, &ctx);
	lunatik_putobject(runtime);
out:
	return action;
}

LUNATIK_EBPF_END();

LUNATIK_EBPF_KFUNC_DEFINE_SET(tc, bpf_luatc_run);

/***
* Unregisters the Lua callback function associated with the current Lunatik runtime.
* After calling this, `bpf_luatc_run` calls targeting this runtime will no longer
* invoke a Lua function (they will likely return an error or default action).
* @function detach
* @treturn nil
* @usage
*   tc.detach()
* @within tc
*/
static int luatc_detach(lua_State *L)
{
	luatc_ctx_t *lctx;
	lunatik_bpf_get_env(L, &luatc_env_key, lctx);
	luaL_unref(L, LUA_REGISTRYINDEX, lctx->callback_ref);
	lctx->callback_ref = LUA_NOREF;
	lua_pop(L, 1);
	lunatik_unregister(L, &luatc_env_key);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by an XDP/eBPF program.
* When an XDP program calls the `bpf_luatc_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime invoking this function must be non-sleepable.
*
* The `bpf_luatc_run` kfunc is called from an eBPF program with the following signature:
* `int bpf_luatc_run(char *key, size_t key_sz, struct __sk_buff *tc_ctx)`
*
* - `key`: A string identifying the Lunatik runtime (e.g., the script name like "examples/filter/sni").
*   This key is used to look up the runtime in Lunatik's internal table of active runtimes.
* - `key_sz`: Length of the key string (including the null terminator).
* - `tc_ctx`: The XDP metadata context (`struct __sk_buff *`).
*
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
* 1. `ctx` (tc.ctx userdata): A context object used to inspect the packet
*    and control the XDP verdict via `ctx:action()`.
*
*   The callback **must not return a value**. If no action is set, the default
*   is `action.PASS`.
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   -- Lua script (e.g., "my_tc_handler.lua" which is run via `lunatik run my_tc_handler.lua`)
*   local tc = require("tc")
*   local action = require("linux.tc")
*
*   local function my_packet_processor(ctx)
*     local skb = ctx:packet()
*     print("Packet received, size:", #skb)
*     ctx:action(action.ACT_OK)
*     return nil
*   end
*   tc.attach(my_packet_processor)
*
*   -- In eBPF C code, to call the above Lua function:
*   -- char rt_key[] = "my_tc_handler.lua"; // Key matches the script name
*   -- int verdict = bpf_luatc_run(rt_key, sizeof(rt_key), ctx);
* @see data
* @within tc
*/
static int luatc_attach(lua_State *L)
{
	lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lunatik_object_t *object = lunatik_newobject(L, &luatc_class, sizeof(luatc_ctx_t), LUNATIK_OPT_NONE);
	luatc_ctx_t *ctx = (luatc_ctx_t *)object->private;

	ctx->skb_obj = luaskb_new(L);
	lunatik_getobject(ctx->skb_obj);
	lunatik_register(L, -1, ctx->skb_obj);
	lua_pop(L, 1);

	ctx->argument = luadata_new(L, LUNATIK_OPT_SINGLE);
	lunatik_getobject(ctx->argument);
	lunatik_register(L, -1, ctx->argument);
	lua_pop(L, 1);

	lua_pushvalue(L, 1);
	ctx->callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	lunatik_register(L, -1, &luatc_env_key);
	lua_pop(L, 1);

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

LUNATIK_CLASSES(tc, &luatc_class);
LUNATIK_NEWLIB(tc, luatc_lib, luatc_classes);

static int __init luatc_init(void)
{
	LUNATIK_EBPF_KFUNC_INIT(tc, BPF_PROG_TYPE_SCHED_CLS);
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
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal/im421@gmail.com>");

