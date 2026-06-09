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
static lunatik_object_t *luasched_percpu = NULL;

typedef struct luasched_ctx_s {
	struct task_struct *task;
	u64                *dsq;
	u64                *slice;
	int                callback_ref;
} luasched_ctx_t;

LUNATIK_PRIVATECHECKER(luasched_ctx_check, luasched_ctx_t *,
	luaL_argcheck(L, private->task != NULL, ix, "ctx is not set");
);

/***
* Sched callback context, valid only while the callback runs.
* It is handed to the callback registered with `sched.attach`; its methods raise
* once the callback returns.
* @type sched_ctx
*/

/***
* Returns the object for the current task.
* @function task
* @treturn task
*/
static int luasched_task(lua_State *L)
{
	luasched_ctx_t *ctx = luasched_ctx_check(L, 1);
	lunatik_object_t *task = luatask_new(L, ctx->task);
	lunatik_pushobject(L, task);
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
static int luasched_slice(lua_State *L)
{
	luasched_ctx_t *ctx = luasched_ctx_check(L, 1);
	*ctx->slice = luaL_checkinteger(L, 2);
	return 0;
}

static const luaL_Reg luasched_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"task", luasched_task},
	{"dsq", luasched_dsq},
	{"slice", luasched_slice},
	{NULL, NULL}
};

static void luasched_release(void *private)
{
	luasched_ctx_t *lctx = (luasched_ctx_t *)private;
	if (lctx->task != NULL) {
		put_task_struct(lctx->task);
		lctx->task = NULL;
	}
}

LUNATIK_OPENER(sched);
static const lunatik_class_t luasched_class = {
	.name    = "sched.ctx",
	.methods = luasched_mt,
	.release = luasched_release,
	.opener  = luaopen_sched,
	.opt     = LUNATIK_OPT_HARDIRQ,
};

static void luasched_handler_cleanup(luasched_ctx_t *lctx)
{
	put_task_struct(lctx->task);
	lctx->task = NULL;
	lctx->dsq = NULL;
	lctx->slice = NULL;
}

static int luasched_handler(lua_State *L, luasched_ctx_t *ctx)
{
	luasched_ctx_t *lctx = lunatik_ebpf_getctx(L, &luasched_env_key);

	if (lctx == NULL)
		return -1;

	get_task_struct(ctx->task);

	lctx->task = ctx->task;
	lctx->dsq = ctx->dsq;
	lctx->slice = ctx->slice;

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
	u64 dsq;
	u64 slice;
};

__bpf_kfunc int bpf_luasched_run(char *key, size_t key__sz, struct task_struct *task, struct task_class *cls)
{
	u64 dsq = SCX_DSQ_GLOBAL;
	u64 slice = SCX_SLICE_DFL;
	int ret;

	if (!cls)
		return -1;

	lunatik_object_t *runtime = lunatik_ebpf_lookupruntime(&luasched_runtimes, &luasched_percpu,
			key, key__sz, raw_smp_processor_id());
	if (runtime == NULL)
		return -1;

	luasched_ctx_t ctx = {
		.task  = task,
		.dsq   = &dsq,
		.slice = &slice,
	};

	lunatik_run(runtime, luasched_handler, ret, &ctx);
	lunatik_putobject(runtime);
	cls->dsq = dsq;
	cls->slice = slice;
	return ret;
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
	luasched_ctx_t *lctx = lunatik_ebpf_getctx(L, &luasched_env_key);

	if (lctx == NULL)
		return -1;

	luaL_unref(L, LUA_REGISTRYINDEX, lctx->callback_ref);
	lctx->callback_ref = LUA_NOREF;
	lua_pop(L, 1);
	lunatik_unregister(L, &luasched_env_key);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by a sched_ext eBPF program.
* When an XDP program calls the `bpf_luasched_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime invoking this function must be non-sleepable.
*
* The `bpf_luasched_run` kfunc is called from an eBPF program with the following signature:
* `int bpf_luasched_run(const char *key, size_t key__sz, struct task_struct *task_struct, struct task_class *cls)`
*
* - `key`: A string identifying the Lunatik runtime (e.g., the script name like "examples/workload/workload").
*   This key is used to look up the runtime in Lunatik's internal table of active runtimes.
* - `key_sz`: Length of the key string (including the null terminator).
* - `task_struct`: The task context (`struct task_struct *`).
* - `cls`: The scheduling decision (dsq and slice).
*
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
*   `ctx`: An `sched_ctx` context object used to inspect the task
*   and control the XDP verdict via `sched_ctx:dsq`.
*
*   The callback need not return a value. If it sets no dispatch queue, `bpf_luasched_run`
*   sets SCX_DSQ_GLOBAL and the verdict is left to the eBPF program.
* @treturn nil
* @raise Error if the current runtime is sleepable or if internal setup fails.
* @usage
*   -- Lua script (e.g., "my_sched_handler.lua" which is run via `lunatik run my_sched_handler.lua hardirq`)
*   local sched = require("sched")
*   local scx = require("linux.scx")
*
*   local function my_scheduler(ctx)
*     local task = ctx:task()
*     if task:comm() == "bash" then
*       ctx:dsq(scx.DSQ_LOCAL)
*       ctx:slice(scx.SLICE_DFL)
*     end
*     return
*   end
*   sched.attach(my_scheduler)
*
*   -- In eBPF C code, to call the above Lua function:
*   -- char rt_key[] = "my_sched_handler.lua"; // Key matches the script name
*   -- int ret = bpf_luasched_run(rt_key, sizeof(rt_key), p, cls);
* @see task
* @within sched
*/
static int luasched_attach(lua_State *L)
{
	lunatik_checkruntime(L, LUNATIK_OPT_HARDIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */
	luasched_detach(L); /* re-attaching replaces the previous callback */

	lunatik_object_t *object = lunatik_newobject(L, &luasched_class, sizeof(luasched_ctx_t), LUNATIK_OPT_NONE);
	luasched_ctx_t *ctx = (luasched_ctx_t *)object->private;

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

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
LUNATIK_CLASSES(sched, &luasched_class);
#else
static const lunatik_class_t *luasched_classes[] = { NULL };
#endif
LUNATIK_NEWLIB(sched, luasched_lib, luasched_classes);

LUNATIK_EBPF_KFUNC_INIT(sched, BPF_PROG_TYPE_STRUCT_OPS);

static void __exit luasched_exit(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
	if (luasched_runtimes != NULL)
		lunatik_putobject(luasched_runtimes);
	if (luasched_percpu != NULL)
		lunatik_putobject(luasched_percpu);
#endif
}

module_init(luasched_init);
module_exit(luasched_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal/im421@gmail.com>");

