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

#include "luadata.h"
#include "luaskb.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <net/pkt_cls.h>

LUNATIK_EBPF_START();

static char luatc_env_key;

static lunatik_object_t *luatc_runtimes = NULL;
static lunatik_object_t *luatc_percpu = NULL;

typedef struct luatc_ctx_s {
	struct __sk_buff *skb;
	int              *action;
	lunatik_object_t *skb_obj;
	int              callback_ref;
} luatc_ctx_t;

LUNATIK_PRIVATECHECKER(luatc_ctx_check, luatc_ctx_t *,
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
	{"action", luatc_action},
	{NULL, NULL}
};

static void luatc_release(void *private)
{
	luatc_ctx_t *lctx = (luatc_ctx_t *)private;
	if (lctx->skb_obj)
		luaskb_clear(lctx->skb_obj);
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
	lskb->skb = NULL;
	lctx->action = NULL;
}

static int luatc_handler(lua_State *L, luatc_ctx_t *ctx)
{
	luatc_ctx_t *lctx = lunatik_ebpf_getctx(L, &luatc_env_key);
	int ret = 0;

	if (lctx == NULL)
		return -1;

	luaskb_t *lskb = (luaskb_t *)lctx->skb_obj->private;

	lskb->skb = (struct sk_buff *)ctx->skb;

	lctx->skb     = ctx->skb;
	lctx->action  = ctx->action;

	lua_rawgeti(L, LUA_REGISTRYINDEX, lctx->callback_ref);
	if (!lua_isfunction(L, -1)) {
		pr_err_ratelimited("callback_ref is not a function\n");
		lua_pop(L, 2);
		ret = -1;
		goto out;
	}

	lua_insert(L, -2);
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		pr_err_ratelimited("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		ret = -1;
		goto out;
	}
out:
	luatc_handler_cleanup(lctx);
	return ret;
}

__bpf_kfunc int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *skb)
{
	int action = -1;
	int ret;

	lunatik_object_t *runtime = lunatik_ebpf_lookupruntime(&luatc_runtimes, &luatc_percpu,
			key, key__sz, raw_smp_processor_id());
	if (runtime == NULL)
		goto out;

	luatc_ctx_t ctx = {
		.skb     = skb,
		.action  = &action,
	};

	lunatik_run(runtime, luatc_handler, ret, &ctx);
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
	luatc_ctx_t *lctx = lunatik_ebpf_getctx(L, &luatc_env_key);

	if (lctx == NULL)
		return -1;

	luaL_unref(L, LUA_REGISTRYINDEX, lctx->callback_ref);
	lctx->callback_ref = LUA_NOREF;
	lua_pop(L, 1);
	lunatik_unregister(L, lctx->skb_obj);
	lunatik_unregister(L, &luatc_env_key);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by an TC/eBPF program.
* When an TC program calls the `bpf_luatc_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime invoking this function must be non-sleepable.
*
* The `bpf_luatc_run` kfunc is called from an eBPF program with the following signature:
* `int bpf_luatc_run(char *key, size_t key__sz, struct __sk_buff *sk_buff)`
*
* - `key`: A string identifying the Lunatik runtime (e.g., the script name like "examples/sniclassify/sni").
*   This key is used to look up the runtime in Lunatik's internal table of active runtimes.
* - `key_sz`: Length of the key string (including the null terminator).
* - `sk_buff`: The TC metadata context (`struct __sk_buff *`).
*
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
*   `ctx`: An `tc_ctx` context object used to inspect the packet
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
*   -- int verdict = bpf_luatc_run(rt_key, sizeof(rt_key), ctx, NULL, 0);
* @see skb
* @within tc
*/
static int luatc_attach(lua_State *L)
{
	lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */
	luatc_detach(L); /* re-attaching replaces the previous callback */

	lunatik_object_t *object = lunatik_newobject(L, &luatc_class, sizeof(luatc_ctx_t), LUNATIK_OPT_NONE);
	luatc_ctx_t *ctx = (luatc_ctx_t *)object->private;

	ctx->skb_obj = luaskb_new(L);
	lunatik_getobject(ctx->skb_obj);
	lunatik_register(L, -1, ctx->skb_obj);
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

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
LUNATIK_CLASSES(tc, &luatc_class);
#else
static const lunatik_class_t *luatc_classes[] = { NULL };
#endif
LUNATIK_NEWLIB(tc, luatc_lib, luatc_classes);

LUNATIK_EBPF_KFUNC_INIT(tc, BPF_PROG_TYPE_SCHED_CLS);

static void __exit luatc_exit(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	if (luatc_runtimes != NULL)
		lunatik_putobject(luatc_runtimes);
	if (luatc_percpu != NULL)
		lunatik_putobject(luatc_percpu);
#endif
}

module_init(luatc_init);
module_exit(luatc_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal/im421@gmail.com>");

