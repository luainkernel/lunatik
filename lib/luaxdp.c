/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
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

static lunatik_object_t *luaxdp_runtimes = NULL;

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

static inline int luaxdp_checkruntimes(void)
{
	const char *key = "runtimes";
	if (luaxdp_runtimes == NULL &&
	   (luaxdp_runtimes = luarcu_gettable(lunatik_env, key, sizeof(key))) == NULL)
		return -1;
	return 0;
}

__bpf_kfunc int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *xdp_ctx, void *arg, size_t arg__sz)
{
	lunatik_object_t *runtime;
	struct xdp_buff *ctx = (struct xdp_buff *)xdp_ctx;
	int action = -1;
	size_t keylen = key__sz - 1;

	if (unlikely(luaxdp_checkruntimes() != 0)) {
		pr_err("couldn't find _ENV.runtimes\n");
		goto out;
	}

	key[keylen] = '\0';
	if ((runtime = luarcu_gettable(luaxdp_runtimes, key, keylen)) == NULL) {
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

/***
* Table of XDP action verdicts.
* These constants define the possible return values from an XDP program (and thus
* from the Lua callback attached via `xdp.attach`) to indicate how the packet
* should be handled.
* (Constants from `<uapi/linux/bpf.h>`)
* @table action
*   @tfield integer ABORTED Indicates an error; packet is dropped. (XDP_ABORTED)
*   @tfield integer DROP Drop the packet silently. (XDP_DROP)
*   @tfield integer PASS Pass the packet to the normal network stack. (XDP_PASS)
*   @tfield integer TX Transmit the packet back out the same interface it arrived on. (XDP_TX)
*   @tfield integer REDIRECT Redirect the packet to another interface or BPF map. (XDP_REDIRECT)
* @within xdp
*/
#define luaxdp_setcallback(L, i)	(lunatik_setregistry((L), (i), luaxdp_callback))

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
	lua_pushnil(L);
	luaxdp_setcallback(L, 1);
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
* @tparam function callback The Lua function to be called. This function receives two arguments:
*
* 1. `buffer` (data): A `data` object representing the network packet buffer (`xdp_md`).
*    The `data` object points to `xdp_ctx->data` and its size is `xdp_ctx->data_end - xdp_ctx->data`.
* 2. `argument` (data): A `data` object representing the `arg` passed from the eBPF program.
*    Its size is `arg_sz`.
*
*   The callback function should return an integer verdict, typically one of the values
*   from the `xdp.action` table (e.g., `xdp.action.PASS`, `xdp.action.DROP`).
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   -- Lua script (e.g., "my_xdp_handler.lua" which is run via `lunatik run my_xdp_handler.lua`)
*   local xdp = require("xdp")
*
*   local function my_packet_processor(packet_buffer, custom_arg)
*     print("Packet received, size:", #packet_buffer)
*     return xdp.action.PASS
*   end
*   xdp.attach(my_packet_processor)
*
*   -- In eBPF C code, to call the above Lua function:
*   -- char rt_key[] = "my_xdp_handler.lua"; // Key matches the script name
*   -- int verdict = bpf_luaxdp_run(rt_key, sizeof(rt_key), ctx, NULL, 0);
* @see xdp.action
* @see data
* @within xdp
*/
static int luaxdp_attach(lua_State *L)
{
	lunatik_checkruntime(L, false);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	luadata_new(L); /* buffer */
	luadata_new(L); /* argument */

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
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	if (luaxdp_runtimes != NULL)
		lunatik_putobject(luaxdp_runtimes);
#endif
}

module_init(luaxdp_init);
module_exit(luaxdp_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

