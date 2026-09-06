/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux Traffic Control (TC) integration.
* This library allows Lua scripts to interact with the kernel's TC subsystem.
* It enables TC/eBPF programs to call Lua functions for packet processing,
* traffic shaping, filtering, and policy enforcement, providing a flexible
* way to implement custom networking logic in Lua at the ingress and egress
* layers of network stack.
*
* The primary mechanism involves a TC program calling the `bpf_luatc_run`
* kfunc, which in turn invokes a Lua callback function previously registered
* using `tc.attach()`.
* @module tc
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bpf.h>

#include <lunatik.h>
#include <lunatik_ebpf.h>

#include "luadata.h"
#include "luaskb.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <net/pkt_cls.h>

LUNATIK_EBPF_START();

typedef struct luatc_ctx_s {
	struct __sk_buff *skb;
	void             *arg;
	size_t            arg__sz;
	int              *action;
	lunatik_object_t *skb_obj;
	lunatik_object_t *argument;
	int              cb;
} luatc_ctx_t;

static const lunatik_class_t luatc_class;

LUNATIK_PRIVATECHECKER(luatc_ctx_check, luatc_ctx_t *, &luatc_class,
	luaL_argcheck(L, private->skb != NULL, ix, "ctx is not set");
);

/***
* TC callback context, valid only while the callback runs.
* It is handed to the callback registered with `tc.attach`; its methods raise
* once the callback returns.
* @type tc_ctx
*/

/***
* Returns the packet object for the current TC context.
* @function tc_ctx:skb
* @treturn skb
*/
static int luatc_skb(lua_State *L)
{
	luatc_ctx_t *ctx = luatc_ctx_check(L, 1);
	lunatik_getregistry(L, ctx->skb_obj);
	return 1;
}

/***
* Returns the argument data buffer passed from eBPF.
* @function tc_ctx:argument
* @treturn data argument buffer
*/
static int luatc_argument(lua_State *L)
{
	luatc_ctx_t *ctx = luatc_ctx_check(L, 1);
	lunatik_getregistry(L, ctx->argument);
	return 1;
}

/***
* Sets the TC verdict action for this packet.
* @function tc_ctx:action
* @tparam integer action TC action constant (e.g. `TC_ACT_OK`, `TC_ACT_SHOT`, ...)
*/
static int luatc_action(lua_State *L)
{
	luatc_ctx_t *ctx = luatc_ctx_check(L, 1);
	*ctx->action = luaL_checkinteger(L, 2);
	return 0;
}

static const luaL_Reg luatc_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"skb", luatc_skb},
	{"argument", luatc_argument},
	{"action", luatc_action},
	{NULL, NULL}
};

static void luatc_release(void *private)
{
	luatc_ctx_t *lctx = (luatc_ctx_t *)private;
	if (lctx->skb_obj)
		luaskb_close(lctx->skb_obj);
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

static inline void luatc_handler_cleanup(luatc_ctx_t *lctx)
{
	luaskb_clear(lctx->skb_obj);
	luadata_clear(lctx->argument);
	lctx->skb = NULL;
	lctx->action = NULL;
}

static int luatc_handler(lua_State *L, luatc_ctx_t *ctx)
{
	luatc_ctx_t *lctx = lunatik_ebpf_getctx(L);
	int ret = 0;

	if (lctx == NULL)
		return -1;

	struct sk_buff *skb = (struct sk_buff *)ctx->skb;

	luaskb_reset(lctx->skb_obj, skb);

	lctx->skb     = ctx->skb;
	lctx->arg     = ctx->arg;
	lctx->arg__sz = ctx->arg__sz;
	lctx->action  = ctx->action;
	luadata_reset(lctx->argument, lctx->arg, lctx->arg__sz, LUADATA_OPT_KEEP);

	ret = lunatik_ebpf_invoke(L, lctx->cb);
	luatc_handler_cleanup(lctx);
	return ret;
}

__bpf_kfunc int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *skb, void *arg, size_t arg__sz)
{
	int action = -1;

	luatc_ctx_t ctx = {
		.skb     = skb,
		.arg     = arg,
		.arg__sz = arg__sz,
		.action  = &action,
	};

	LUNATIK_EBPF_RUN(key, key__sz, luatc_handler, &ctx);
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
	luatc_ctx_t *lctx = lunatik_ebpf_getctx(L);

	if (lctx == NULL)
		return 0;

	lunatik_ebpf_unbind(L, &lctx->cb);
	lunatik_ebpf_detach(L, lctx, skb_obj);
	lunatik_ebpf_detach(L, lctx, argument);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by a TC/eBPF program.
* When a TC program calls the `bpf_luatc_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime invoking this function must be non-sleepable.
*
* The `bpf_luatc_run` kfunc is called from an eBPF program with the following signature:
* `int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *sk_buff, void *arg, size_t arg__sz)`
*
* - `key`: A string identifying the Lunatik runtime (e.g., the script name like "examples/sniclassify/sni").
*   This key is used to look up the runtime in Lunatik's internal table of active runtimes.
* - `key_sz`: Length of the key string (including the null terminator).
* - `sk_buff`: The TC metadata context (`struct __sk_buff *`).
* - `arg`: A pointer to arbitrary data passed from eBPF to Lua.
* - `arg_sz`: The size of the `arg` data.
*
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
*   `ctx`: A `tc_ctx` context object used to inspect the packet
*   and control the TC verdict via `tc_ctx:action`.
*
*   The callback need not return a value. If it sets no action, `bpf_luatc_run`
*   returns `-1` and the verdict is left to the eBPF program.
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   -- Lua script (e.g., "my_tc_handler.lua" which is run via `lunatik run my_tc_handler.lua softirq`)
*   local tc = require("tc")
*   local action = require("linux.tc")
*
*   local function my_traffic_shaper(ctx)
*     local skb = ctx:skb()
*     print("Packet received, size:", #skb)
*     ctx:action(action.ACT_OK)
*     return
*   end
*   tc.attach(my_traffic_shaper)
*
*   -- In eBPF C code, to call the above Lua function:
*   -- char rt_key[] = "my_tc_handler.lua"; // Key matches the script name
*   -- int verdict = bpf_luatc_run(rt_key, sizeof(rt_key), skb, NULL, 0);
* @see skb
* @see data
* @within tc
*/
static int luatc_attach(lua_State *L)
{
	lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */
	luatc_detach(L); /* re-attaching replaces the previous callback */

	lunatik_object_t *object = lunatik_newobject(L, &luatc_class, sizeof(luatc_ctx_t), LUNATIK_OPT_NONE);
	luatc_ctx_t *ctx = (luatc_ctx_t *)object->private;

	lunatik_ebpf_attach(L, ctx, skb_obj, luaskb_new);
	lunatik_ebpf_attach(L, ctx, argument, luadata_new, LUNATIK_OPT_SINGLE);

	lunatik_ebpf_bind(L, 1, &ctx->cb);
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

LUNATIK_EBPF_NEWLIB(tc, luatc_lib, &luatc_class);

LUNATIK_EBPF_KFUNC_INIT(tc, BPF_PROG_TYPE_SCHED_CLS);

LUNATIK_EBPF_EXIT(tc);

module_init(luatc_init);
module_exit(luatc_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>");

