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
* using `xdp.attach`.
* @module xdp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bpf.h>

#include <lunatik.h>
#include <lunatik_ebpf.h>

#include "luadata.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <net/xdp.h>

LUNATIK_EBPF_START();

typedef struct luaxdp_ctx_s {
	struct xdp_buff  *xdp;
	void             *arg;
	size_t            arg__sz;
	int              *action;
	lunatik_object_t *packet;
	lunatik_object_t *argument;
	int              cb;
} luaxdp_ctx_t;

static const lunatik_class_t luaxdp_class;

LUNATIK_PRIVATECHECKER(luaxdp_ctx_check, luaxdp_ctx_t *, &luaxdp_class,
	luaL_argcheck(L, private->xdp != NULL, ix, "ctx is not set");
);

/***
* XDP callback context, valid only while the callback runs.
* It is handed to the callback registered with `xdp.attach`; its methods raise
* once the callback returns.
* @type xdp_ctx
*/

/***
* Returns the packet data buffer for the current XDP context.
* @function xdp_ctx:packet
* @treturn data packet buffer
*/
static int luaxdp_packet(lua_State *L)
{
	luaxdp_ctx_t *ctx = luaxdp_ctx_check(L, 1);
	lunatik_getregistry(L, ctx->packet);
	return 1;
}

/***
* Returns the argument data buffer passed from eBPF.
* @function xdp_ctx:argument
* @treturn data argument buffer
*/
static int luaxdp_argument(lua_State *L)
{
	luaxdp_ctx_t *ctx = luaxdp_ctx_check(L, 1);
	lunatik_getregistry(L, ctx->argument);
	return 1;
}

/***
* Sets the XDP verdict action for this packet.
* @function xdp_ctx:action
* @tparam integer action XDP action constant (e.g. `XDP_PASS`, `XDP_DROP`, ...)
*/
static int luaxdp_action(lua_State *L)
{
	luaxdp_ctx_t *ctx = luaxdp_ctx_check(L, 1);
	*ctx->action = luaL_checkinteger(L, 2);
	return 0;
}

static const luaL_Reg luaxdp_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"packet", luaxdp_packet},
	{"argument", luaxdp_argument},
	{"action", luaxdp_action},
	{NULL, NULL}
};

static void luaxdp_release(void *private)
{
	luaxdp_ctx_t *lctx = (luaxdp_ctx_t *)private;
	if (lctx->packet)
		luadata_close(lctx->packet);
	if (lctx->argument)
		luadata_close(lctx->argument);
}

LUNATIK_OPENER(xdp);
static const lunatik_class_t luaxdp_class = {
	.name    = "xdp.ctx",
	.methods = luaxdp_mt,
	.release = luaxdp_release,
	.opener  = luaopen_xdp,
	.opt     = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

static inline void luaxdp_handler_cleanup(luaxdp_ctx_t *lctx)
{
	luadata_clear(lctx->packet);
	luadata_clear(lctx->argument);
	lctx->xdp = NULL;
	lctx->action = NULL;
}

static int luaxdp_handler(lua_State *L, luaxdp_ctx_t *ctx)
{
	luaxdp_ctx_t *lctx = lunatik_ebpf_getctx(L);
	int ret = 0;

	if (lctx == NULL)
		return -1;

	lctx->xdp     = ctx->xdp;
	lctx->arg     = ctx->arg;
	lctx->arg__sz = ctx->arg__sz;
	lctx->action  = ctx->action;
	luadata_reset(lctx->packet, lctx->xdp->data, lctx->xdp->data_end - lctx->xdp->data, LUADATA_OPT_KEEP);
	luadata_reset(lctx->argument, lctx->arg, lctx->arg__sz, LUADATA_OPT_KEEP);

	ret = lunatik_ebpf_invoke(L, lctx->cb);
	luaxdp_handler_cleanup(lctx);
	return ret;
}

__bpf_kfunc int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *xdp_ctx, void *arg, size_t arg__sz)
{
	int action = -1;

	luaxdp_ctx_t ctx = {
		.xdp     = (struct xdp_buff *)xdp_ctx,
		.arg     = arg,
		.arg__sz = arg__sz,
		.action  = &action,
	};

	LUNATIK_EBPF_RUN(key, key__sz, luaxdp_handler, &ctx);
	return action;
}

LUNATIK_EBPF_END();

LUNATIK_EBPF_KFUNC_DEFINE_SET(xdp, bpf_luaxdp_run);

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
	luaxdp_ctx_t *lctx = lunatik_ebpf_getctx(L);

	if (lctx == NULL)
		return 0;

	lunatik_ebpf_unbind(L, &lctx->cb);
	lunatik_ebpf_detach(L, lctx, packet);
	lunatik_ebpf_detach(L, lctx, argument);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by an XDP/eBPF program.
* When an XDP program calls the `bpf_luaxdp_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime invoking this function must be non-sleepable.
*
* The `bpf_luaxdp_run` kfunc is called from an eBPF program with the following signature:
* `int bpf_luaxdp_run(char *key, size_t key_sz, struct xdp_md *xdp_md, void *arg, size_t arg_sz)`
*
* - `key`: A string identifying the Lunatik runtime (e.g., the script name like "examples/filter/sni").
*   This key is used to look up the runtime in Lunatik's internal table of active runtimes.
* - `key_sz`: Length of the key string (including the null terminator).
* - `xdp_md`: The XDP metadata context (`struct xdp_md *`).
* - `arg`: A pointer to arbitrary data passed from eBPF to Lua.
* - `arg_sz`: The size of the `arg` data.
*
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
*   `ctx`: An `xdp_ctx` context object used to inspect the packet
*   and control the XDP verdict via `xdp_ctx:action`.
*
*   The callback need not return a value. If it sets no action, `bpf_luaxdp_run`
*   returns `-1` and the verdict is left to the eBPF program.
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   -- Lua script (e.g., "my_xdp_handler.lua" which is run via `lunatik run my_xdp_handler.lua softirq`)
*   local xdp = require("xdp")
*   local action = require("linux.xdp")
*
*   local function my_packet_processor(ctx)
*     local pkt = ctx:packet()
*     print("Packet received, size:", #pkt)
*     ctx:action(action.PASS)
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
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */
	luaxdp_detach(L); /* re-attaching replaces the previous callback */

	lunatik_object_t *object = lunatik_newobject(L, &luaxdp_class, sizeof(luaxdp_ctx_t), LUNATIK_OPT_NONE);
	luaxdp_ctx_t *ctx = (luaxdp_ctx_t *)object->private;

	lunatik_ebpf_attach(L, ctx, packet, luadata_new, LUNATIK_OPT_SINGLE);
	lunatik_ebpf_attach(L, ctx, argument, luadata_new, LUNATIK_OPT_SINGLE);

	lunatik_ebpf_bind(L, 1, &ctx->cb);
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

LUNATIK_EBPF_NEWLIB(xdp, luaxdp_lib, &luaxdp_class);

LUNATIK_EBPF_KFUNC_INIT(xdp, BPF_PROG_TYPE_XDP);

LUNATIK_EBPF_EXIT(xdp);

module_init(luaxdp_init);
module_exit(luaxdp_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

