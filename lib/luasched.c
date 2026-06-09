/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux Exensible Scheduler (sched_ext) integration.
* This library allows Lua scripts to interact with the kernel's sched_ext subsystem.
* It enables sched_ext/eBPF programs to call Lua functions for task scheduling,
* providing a flexible way to implement custom scheduling logic in Lua.
*
* The primary mechanism involves an sched_ext program calling the `bpf_luasched_run`
* kfunc, which in turn invokes a Lua callback function previously registered
* using `sched.attach()`.
* @module sched
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bpf.h>
#include <linux/sched/ext.h>

#include <lunatik.h>
#include <lunatik_ebpf.h>

#include "luarcu.h"
#include "luatask.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <linux/sched.h>

LUNATIK_EBPF_START();

static char luasched_env_key;

static lunatik_object_t *luasched_runtimes = NULL;

typedef struct luasched_ctx_s {
	struct task_struct *task;
	int                *dsq;
	int                *slice_ns;
	lunatik_object_t   *task_obj;
	int                callback_ref;
} luasched_ctx_t;

LUNATIK_PRIVATECHECKER(luasched_ctx_check, luasched_ctx_t *,
	luaL_argcheck(L, private->task != NULL, ix, "ctx is not set");
);

/***
* Returns the object for the current task.
* @function task
* @treturn task
*/
static int luasched_task(lua_State *L)
{
	luasched_ctx_t *ctx = luasched_ctx_check(L, 1);
	lunatik_getregistry(L, ctx->task_obj);
	return 1;
}

/***
* Sets the sched_ext dispatch queue for this task.
* @function dsq
* @tparam integer dispatch queue to set for the task
*/
static int luasched_dsq(lua_State *L)
{
	luasched_ctx_t *ctx = luasched_ctx_check(L, 1);
	*ctx->dsq = luaL_checkinteger(L, 2);
	return 0;
}

/***
* Sets the sched_ext slice in nanoseconds for this task.
* @function dsq
* @tparam integer slice in ns to set for the task
*/
static int luasched_slice_ns(lua_State *L)
{
	luasched_ctx_t *ctx = luasched_ctx_check(L, 1);
	*ctx->slice_ns = luaL_checkinteger(L, 2);
	return 0;
}

static const luaL_Reg luasched_mt[] = {
	{"__gc",		lunatik_deleteobject},
	{"task",		luasched_task},
	{"dsq",			luasched_dsq},
	{"slice_ns",	luasched_slice_ns},
	{NULL, NULL}
};

static void luasched_release(void *private)
{
	luasched_ctx_t *lctx = (luasched_ctx_t *)private;
	if (lctx->task != NULL) {
		put_task_struct(lctx->task);
		lctx->task = NULL;
	}
	lctx->task_obj = NULL;
}

LUNATIK_OPENER(sched);
static const lunatik_class_t luasched_class = {
	.name    = "sched.ctx",
	.methods = luasched_mt,
	.release = luasched_release,
	.opener  = luaopen_sched,
	.opt     = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE,
};

static void luasched_handler_cleanup(luasched_ctx_t *lctx)
{
	put_task_struct(lctx->task);
	lctx->task = NULL;
	lctx->task_obj->private = NULL;
	lctx->dsq = NULL;
	lctx->slice_ns = NULL;
}

static int luasched_handler(lua_State *L, luasched_ctx_t *ctx)
{
	luasched_ctx_t *lctx;
	lunatik_bpf_get_env(L, &luasched_env_key, lctx);
	get_task_struct(ctx->task);

	lctx->task = ctx->task;
	lctx->dsq      = ctx->dsq;
	lctx->slice_ns = ctx->slice_ns;
	lctx->task_obj->private = ctx->task;

	lua_rawgeti(L, LUA_REGISTRYINDEX, lctx->callback_ref);
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 2);
		pr_err("callback_ref is not a valid function\n");
		luasched_handler_cleanup(lctx);
		return -1;
	}

	lua_insert(L, -2);
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		luasched_handler_cleanup(lctx);
		return -1;
	}

	luasched_handler_cleanup(lctx);
	return 0;
}

struct task_class {
	s32 dsq;
	u64 slice_ns;
};

__bpf_kfunc int bpf_luasched_run(char *key, size_t key__sz, struct task_struct *task, struct task_class *cls)
{
	int dsq = -1;
	int slice_ns = -1;

	if (!cls)
		return -EINVAL;

	lunatik_object_t *runtime = lunatik_ebpf_lookup(luasched_runtimes, key, key__sz);
	if (runtime == NULL)
		return -ENOENT;

	luasched_ctx_t ctx = {
		.task     = task,
		.dsq      = &dsq,
		.slice_ns = &slice_ns,
	};

	lunatik_run(runtime, luasched_handler, dsq, &ctx);
	lunatik_putobject(runtime);
	cls->dsq = dsq;
	cls->slice_ns = (slice_ns == -1) ? SCX_SLICE_DFL : (u64)slice_ns;
	return 0;
}

LUNATIK_EBPF_END();

LUNATIK_EBPF_KFUNC_DEFINE_SET(sched, bpf_luasched_run);

/***
* Unregisters the Lua callback function associated with the current Lunatik runtime.
* After calling this, `bpf_luasched_run` calls targeting this runtime will no longer
* invoke a Lua function (they will likely return an error or default action).
* @function detach
* @treturn nil
* @usage
*   sched.detach()
* @within sched
*/
static int luasched_detach(lua_State *L)
{
	luasched_ctx_t *lctx;
	lunatik_bpf_get_env(L, &luasched_env_key, lctx);
	luaL_unref(L, LUA_REGISTRYINDEX, lctx->callback_ref);
	lctx->callback_ref = LUA_NOREF;
	lua_pop(L, 1);
	lunatik_unregister(L, &luasched_env_key);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by an XDP/eBPF program.
* When an XDP program calls the `bpf_luasched_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime invoking this function must be non-sleepable.
*
* The `bpf_luasched_run` kfunc is called from an eBPF program with the following signature:
* `int bpf_luasched_run(char *key, size_t key_sz, struct __sk_buff *sched_ctx)`
*
* - `key`: A string identifying the Lunatik runtime (e.g., the script name like "examples/filter/sni").
*   This key is used to look up the runtime in Lunatik's internal table of active runtimes.
* - `key_sz`: Length of the key string (including the null terminator).
* - `sched_ctx`: The task context (`struct task_struct *`).
*
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
* 1. `ctx` (sched.ctx userdata): A context object used to inspect the task
*    and control the sched_ext dsq via `ctx:dsq()`.
*
*   The callback **must not return a value**. If no dsq is set, the default
*   is SCX_DSQ_GLOBAL.
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   -- Lua script (e.g., "my_sched_handler.lua" which is run via `lunatik run my_sched_handler.lua`)
*   local sched = require("sched")
*   local sched_ext = require("linux.sched_ext")
*
*   local function my_task_processor(ctx)
*     local task = ctx:task()
*     if task:comm() == "bash" then
*       ctx:dsq(sched_ext.LOCAL)
*       ctx:slice_ns(sched_ext.BYPASS)
*     end
*     return nil
*   end
*   sched.attach(my_task_processor)
*
*   -- In eBPF C code, to call the above Lua function:
*   -- char rt_key[] = "my_sched_handler.lua"; // Key matches the script name
*   -- int dsq = bpf_luasched_run(rt_key, sizeof(rt_key), ctx);
* @see data
* @within sched
*/
static int luasched_attach(lua_State *L)
{
	lunatik_checkruntime(L, LUNATIK_OPT_HARDIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lunatik_object_t *object = lunatik_newobject(L, &luasched_class, sizeof(luasched_ctx_t), LUNATIK_OPT_NONE);
	luasched_ctx_t *ctx = (luasched_ctx_t *)object->private;

	ctx->task_obj = luatask_new(L, NULL);
	lunatik_pushobject(L, ctx->task_obj);
	lunatik_register(L, -1, ctx->task_obj);
	lua_pop(L, 1);

	lua_pushvalue(L, 1);
	ctx->callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);

	lua_pushvalue(L, -1);

	lunatik_register(L, -1, &luasched_env_key);
	lua_pop(L, 1);

	return 0;
}
#endif

static const luaL_Reg luasched_lib[] = {
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	{"attach", luasched_attach},
	{"detach", luasched_detach},
#endif
	{NULL, NULL}
};

LUNATIK_CLASSES(sched, &luasched_class);
LUNATIK_NEWLIB(sched, luasched_lib, luasched_classes);

static int __init luasched_init(void)
{
	LUNATIK_EBPF_KFUNC_INIT(sched, BPF_PROG_TYPE_STRUCT_OPS);
}

static void __exit luasched_exit(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	if (luasched_runtimes != NULL)
		lunatik_putobject(luasched_runtimes);
#endif
}

module_init(luasched_init);
module_exit(luasched_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal/im421@gmail.com>");

