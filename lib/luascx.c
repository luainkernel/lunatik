/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux Extensible Scheduler (sched_ext) integration.
* This library allows Lua scripts to interact with the kernel's sched_ext subsystem.
* It enables sched_ext/eBPF programs to call Lua functions for task scheduling,
* providing a flexible way to implement custom scheduling logic in Lua.
*
* The primary mechanism involves an sched_ext program calling the `bpf_luascx_run`
* kfunc, which in turn invokes a Lua callback function previously registered
* using `scx.attach()`.
*
* The callback runs inside the sched_ext operation that calls the kfunc, and `ops.enqueue`
* runs with the runqueue lock of its CPU held, so a callback must not call `print`, a
* completion's `complete` or a mailbox's `send`: each can wake a task, and the wakeup takes
* that lock again on a CPU that already holds it. An allocation the callback's Lua makes
* under memory pressure, which can wake kswapd, and the log of an error the callback raises
* can wake a task the same way.
*
* Needs 6.12 and later, with `CONFIG_SCHED_CLASS_EXT`; without it the module loads
* and offers `attach`, which raises `EOPNOTSUPP`, and `detach`, which does nothing.
* The kfunc needs the module's BTF: run `sudo make btf_install` before `make`, or the kernel logs
* `missing module BTF, cannot register kfuncs` and an eBPF program that calls
* `bpf_luascx_run` does not load. The eBPF side is a sched_ext `struct_ops`
* scheduler; `tests/scx/scx_pass.bpf.c` with `tests/scx/pass.lua` is a worked
* pair.
* @module scx
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bpf.h>

#include <lunatik.h>

#include "luakfunc.h"
#include "luarcu.h"
#include "luatask.h"

#ifdef CONFIG_SCHED_CLASS_EXT
#include <linux/btf.h>
#include <linux/btf_ids.h>
#include <linux/sched.h>
#include <linux/sched/ext.h>

LUAKFUNC_START();

struct luascx_task_class {
	u64 dsq;
	u64 slice;
};

typedef struct luascx_ctx_s {
	struct task_struct *task;
	lunatik_object_t   *task_obj;
	struct luascx_task_class *cls;
	int                cb;
} luascx_ctx_t;

static const lunatik_class_t luascx_class;

LUNATIK_PRIVATECHECKER(luascx_ctx_check, luascx_ctx_t *, &luascx_class,
	luaL_argcheck(L, private->task != NULL, ix, "ctx is not set");
);

/***
* sched_ext callback context, valid only while the callback runs.
* It is handed to the callback registered with `scx.attach`; its methods raise
* once the callback returns.
* @type scx_ctx
*/

/***
* Returns the object for the current task.
* The same task object is reused for every callback: it is valid only during the
* callback that returned it, and later it raises or reads the task of the callback
* then running.
* @function scx_ctx:task
* @treturn task
*/
static int luascx_task(lua_State *L)
{
	luascx_ctx_t *ctx = luascx_ctx_check(L, 1);
	lunatik_getregistry(L, ctx->task_obj);
	return 1;
}

static const luaL_Reg luascx_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"task", luascx_task},
	{NULL, NULL}
};

static void luascx_release(void *private)
{
	luascx_ctx_t *lctx = (luascx_ctx_t *)private;
	if (lctx->task_obj)
		luatask_close(lctx->task_obj);
}

static const lunatik_class_t luascx_class = {
	.name    = "scx.ctx",
	.methods = luascx_mt,
	.release = luascx_release,
	.opt     = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE,
	.owner   = THIS_MODULE,
};

static void luascx_handler_cleanup(luascx_ctx_t *lctx)
{
	luatask_clear(lctx->task_obj);
	lctx->task = NULL;
}

#define luascx_isoptional(type)	((type) == LUA_TNIL || (type) == LUA_TNUMBER)

static int luascx_decision(lua_State *L, luascx_ctx_t *ctx)
{
	int dsq = lua_type(L, -2);
	int slice = lua_type(L, -1);

	if (dsq == LUA_TNIL && slice == LUA_TNIL)
		return -1;

	if (!luascx_isoptional(dsq) || !luascx_isoptional(slice)) {
		pr_err_ratelimited("invalid task class\n");
		return -1;
	}

	ctx->cls->dsq = dsq == LUA_TNUMBER ? lua_tointeger(L, -2) : SCX_DSQ_GLOBAL;
	ctx->cls->slice = slice == LUA_TNUMBER ? lua_tointeger(L, -1) : SCX_SLICE_DFL;
	return 0;
}

static int luascx_handler(lua_State *L, luascx_ctx_t *ctx)
{
	luascx_ctx_t *lctx = luakfunc_getctx(L);
	int ret = 0;

	if (lctx == NULL)
		return -1;

	struct task_struct *task = (struct task_struct *)ctx->task;

	luatask_reset(lctx->task_obj, task);

	lctx->task = ctx->task;

	ret = luakfunc_invoke(L, lctx->cb, 2);
	luascx_handler_cleanup(lctx);
	return ret < 0 ? ret : luascx_decision(L, ctx);
}

__bpf_kfunc int bpf_luascx_run(char *key, size_t key__sz, struct task_struct *task, struct luascx_task_class *cls)
{
	int ret = -1;

	if (!cls)
		return -1;

	luascx_ctx_t ctx = {
		.task = task,
		.cls  = cls,
	};

	LUAKFUNC_RUN(key, key__sz, luascx_handler, ret, &ctx);
	return ret;
}

LUAKFUNC_END();

LUAKFUNC_DEFINE_SET(scx, bpf_luascx_run);

/***
* Unregisters the Lua callback function associated with the current Lunatik runtime.
* After calling this, `bpf_luascx_run` calls targeting this runtime invoke no Lua function:
* they log `no callback attached`, return -1 and leave the decision to the eBPF program.
* @function detach
* @treturn nil
* @usage
*   scx.detach()
* @within scx
*/
static int luascx_detach(lua_State *L)
{
	luascx_ctx_t *lctx = luakfunc_findctx(L);

	if (lctx == NULL)
		return 0;

	luakfunc_unbind(L, &lctx->cb);
	luakfunc_detach(L, lctx, task_obj);
	return 0;
}

/***
* Registers a Lua callback function to be invoked by a sched_ext eBPF program.
* When a sched_ext program calls the `bpf_luascx_run` kfunc, Lunatik will execute
* the registered Lua `callback` associated with the current Lunatik runtime.
* The runtime must be a hardirq one (`lunatik run -c hardirq <script>`).
* Calling it again replaces the previous callback.
*
* The eBPF program declares the kfunc as:
*
*     extern int bpf_luascx_run(char *key, size_t key__sz,
*         struct task_struct *task, struct luascx_task_class *cls) __ksym;
*
* - `key`: the name of the Lunatik runtime, the script as given to `lunatik run`
*   without `.lua` (e.g. "sched/policy"; a path keeps its directory). It is looked up
*   in Lunatik's table of active runtimes.
* - `key__sz`: `sizeof` the key array, the NUL terminator included.
* - the task pointer: the task being scheduled.
* - `cls`: where the decision is written, a struct of two `u64`, the dispatch queue
*   and then the slice.
*
* It returns 0 once the callback decided and `cls` is filled, and -1, leaving `cls` as
* it was, when `cls` is NULL or no callback decided.
*
* @function attach
* @tparam function callback Lua function to call. It receives one argument:
*
*   `ctx`: An `scx_ctx` context object used to inspect the task.
*
*   It returns the decision, the dispatch queue and then the slice in nanoseconds,
*   which `bpf_luascx_run` writes to `cls`; a nil one takes `SCX_DSQ_GLOBAL` or
*   `SCX_SLICE_DFL`. When it returns neither, or raises, `bpf_luascx_run` returns -1
*   and the decision is left to the eBPF program; a value that is not a number is logged
*   as `invalid task class` and answered the same way.
* @treturn nil
* @raise `EOPNOTSUPP` on a kernel without sched_ext; `runtime context mismatch` unless the
*   runtime is hardirq; `not allowed while the runtime closes` from a finalizer that runs at its
*   close; or on allocation failure.
* @usage
*   -- sched/policy.lua, run with `lunatik run -c hardirq sched/policy`
*   local scx = require("scx")
*   local ext = require("linux.scx")
*
*   local function my_scheduler(ctx)
*     local task = ctx:task()
*     if task:comm() == "bash" then
*       return ext.DSQ_LOCAL, ext.SLICE_DFL
*     end
*   end
*   scx.attach(my_scheduler)
*
*   -- In eBPF C code, to call the above Lua function:
*   -- char rt_key[] = "sched/policy"; // the script, without .lua
*   -- int ret = bpf_luascx_run(rt_key, sizeof(rt_key), p, cls);
* @see task
* @within scx
*/
static int luascx_attach(lua_State *L)
{
	lunatik_checkruntime(L, luascx_class.name, LUNATIK_OPT_HARDIRQ);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */
	luascx_detach(L); /* re-attaching replaces the previous callback */

	lunatik_object_t *object = lunatik_newobject(L, &luascx_class, sizeof(luascx_ctx_t), LUNATIK_OPT_NONE);
	luascx_ctx_t *ctx = (luascx_ctx_t *)object->private;

	luakfunc_attach(L, ctx, task_obj, luatask_attach, NULL);

	luakfunc_bind(L, 1, &ctx->cb);
	return 0;
}

static const luaL_Reg luascx_lib[] = {
	{"attach", luascx_attach},
	{"detach", luascx_detach},
	{NULL, NULL}
};

LUAKFUNC_NEWLIB(scx, luascx_lib, &luascx_class);

LUAKFUNC_INIT(scx, BPF_PROG_TYPE_STRUCT_OPS);

LUAKFUNC_EXIT(scx);
#else
static const luaL_Reg luascx_lib[] = {
	{"attach", lunatik_unsupported},
	{"detach", lunatik_nop},
	{NULL, NULL}
};

LUNATIK_NEWLIB(scx, luascx_lib, NULL);

static int __init luascx_init(void)
{
	return 0;
}

static void __exit luascx_exit(void)
{
}
#endif

module_init(luascx_init);
module_exit(luascx_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>");

