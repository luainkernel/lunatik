/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Kernel thread primitives.
* Thread objects are created in a process runtime alone: in a softirq or hardirq runtime
* `thread.run` has no runtime object to take. `shouldstop` answers `false` outside a kernel
* thread, and `stop` on a thread already stopped logs a warning and returns `true`.
* @module thread
* @usage
*   -- body.lua, run with `lunatik spawn body`
*   local thread = require("thread")
*   local linux  = require("linux")
*
*   local function body()
*   	while not thread.shouldstop() do
*   		linux.schedule(100)
*   	end
*   end
*   return body
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kthread.h>
#include <linux/sched/task.h>

#include <lunatik.h>

#include "luatask.h"

/***
* Represents a kernel thread object.
* @type thread
*/

typedef struct luathread_s {
	struct task_struct *task;
	lunatik_object_t *runtime;
	int nargs;
} luathread_t;

static int luathread_run(lua_State *L);
static void luathread_popargs(lunatik_object_t *runtime, int nargs);
static const lunatik_class_t luathread_class;

static int luathread_resume(lua_State *L, luathread_t *thread)
{
	int nresults;
	int status = lua_resume(L, NULL, thread->nargs, &nresults);
	if (status != LUA_OK && status != LUA_YIELD) {
		pr_err("[%p] %s\n", thread, lunatik_errmsg(L));
		lua_pop(L, 1);
		return -ENOEXEC;
	}
	lua_pop(L, nresults);
	return 0;
}

static int luathread_func(void *data)
{
	lunatik_object_t *object = (lunatik_object_t *)data;
	luathread_t *thread = (luathread_t *)object->private;
	int ret;

	lunatik_run(thread->runtime, luathread_resume, ret, thread);

	__module_get(THIS_MODULE); /* the put below can drop the object's, and this function runs on after it */
	lunatik_putobject(object);
	module_put_and_kthread_exit(ret);
}

/***
* Checks if the current thread has been signaled to stop.
* @function shouldstop
* @within thread
* @treturn boolean `true` if the thread should stop, `false` otherwise.
* @usage
* while not thread.shouldstop() do
*   linux.schedule(100)
* end
* @see stop
*/
static int luathread_shouldstop(lua_State *L)
{
	lua_pushboolean(L, lunatik_iskthread() ? (int)kthread_should_stop() : 0);
	return 1;
}

static struct task_struct *luathread_claim(lua_State *L, lunatik_object_t *object)
{
	luathread_t *thread = (luathread_t *)object->private;

	lunatik_try(L, lunatik_lockkillable, object);
	struct task_struct *task = thread->task;
	if (task != NULL && lunatik_isowner(thread->runtime)) { /* the body runs under its lock */
		lunatik_unlock(object);
		luaL_error(L, LUNATIK_ERR_OWNER);
	}
	thread->task = NULL; /* the exit kthread_stop waits for is completed once */
	lunatik_unlock(object);
	return task;
}

/***
* Stops a running kernel thread.
* Signals the thread to stop and waits for it to exit. A body waiting for a runtime's lock,
* or for the lock a shared object's method takes, leaves that wait with "EINTR". A
* to-be-closed variable holding the thread stops it the same way. A stop made while another
* stop of the same thread waits for it returns at once, before the thread has exited.
* @function stop
* @treturn boolean `false` if the body it stopped raised, `true` otherwise, for a thread
*   already stopped or being stopped too
* @raise "not allowed under RTNL" from a netdevice callback, in whatever runtime or coroutine
*   its task runs: the stop waits for the body, and a body that registers a netdevice notifier,
*   sends a netlink request or joins a multicast group waits on the RTNL that task holds;
*   "not allowed from the runtime itself" from under the lock of the thread's runtime, the
*   contexts `runtime:stop` names, the thread's own body among them, where the stop would wait
*   on a body that runs under that lock; "EINTR" if the stop of the calling kernel thread, or a
*   fatal signal to any other task, ends its wait for the thread's lock
* @usage
* my_thread:stop()
*/
static int luathread_stop(lua_State *L)
{
	lunatik_checkrtnl(L);
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luathread_class);
	luathread_t *thread = (luathread_t *)object->private;
	lunatik_object_t *runtime = thread->runtime;
	struct task_struct *task = luathread_claim(L, object);

	int result = 0;
	if (task != NULL) {
		result = kthread_stop(task);

		put_task_struct(task);
		if (result == -EINTR) {
			luathread_popargs(runtime, thread->nargs);
			lunatik_putobject(object);
			pr_warn("[%p] thread has never run\n", thread);
		}
		else if (result == -ENOEXEC)
			pr_warn("[%p] thread has failed to execute\n", thread);
		lunatik_putobject(runtime); /* a last put runs its finalizers, which may stop this thread */
	}
	else
		pr_warn("[%p] thread has already stopped\n", thread);
	lua_pushboolean(L, result != -ENOEXEC);
	return 1;
}

/***
* Returns a task object for the kernel task associated with the thread.
* The thread holds a reference to it, so the object stays readable after the
* body returned, reporting the task as it ended. `stop` releases that
* reference: the object returned once a stop began, before the thread has
* exited too, has no task, and its methods raise "closed object".
* @function task
* @treturn task
* @usage
* local t = my_thread:task()
* print(t:pid(), t:comm())
*/
static int luathread_task(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luathread_class);
	luathread_t *thread = (luathread_t *)object->private;

	luatask_new(L, thread->task);
	return 1;
}

static void luathread_release(void *private)
{
	luathread_t *thread = (luathread_t *)private;

	if (thread->task != NULL) {
		put_task_struct(thread->task);
		lunatik_putobject(thread->runtime);
	}
}

static const luaL_Reg luathread_lib[] = {
	{"run", luathread_run},
	{"shouldstop", luathread_shouldstop},
	{NULL, NULL}
};

static const luaL_Reg luathread_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", luathread_stop},
	{"stop", luathread_stop},
	{"task", luathread_task},
	{NULL, NULL}
};

static const lunatik_class_t luathread_class = {
	.name = "thread",
	.methods = luathread_mt,
	.release = luathread_release,
	.opt = LUNATIK_OPT_MONITOR,
	.owner = THIS_MODULE,
};

#define luathread_new(L)	(lunatik_newobject((L), &luathread_class, sizeof(luathread_t), LUNATIK_OPT_NONE))
#define LUATHREAD_ARGIX		3

static void luathread_checkargs(lua_State *L, int nargs)
{
	int i;

	for (i = 0; i < nargs; i++)
		lunatik_checkshareable(L, LUATHREAD_ARGIX + i);
}

static void luathread_pushargs(lua_State *L, lunatik_object_t *runtime, int nargs)
{
	lua_State *Lto;
	int status = LUA_OK;

	lunatik_try(L, lunatik_lockkillable, runtime);
	Lto = lunatik_isready(runtime) ? lunatik_getstate(runtime) : NULL;
	if (Lto != NULL && nargs > 0 && (status = lunatik_copyobjects(Lto, L, LUATHREAD_ARGIX, nargs)) != LUA_OK)
		lua_pop(Lto, 1); /* error message */
	lunatik_unlock(runtime);

	luaL_argcheck(L, Lto != NULL, 1, "stopped runtime"); /* raising under the lock would skip the unlock */
	if (status != LUA_OK)
		luaL_error(L, "couldn't pass the thread arguments");
}

static void luathread_popargs(lunatik_object_t *runtime, int nargs)
{
	lunatik_lock(runtime);
	if (lunatik_isready(runtime))
		lua_pop(lunatik_getstate(runtime), nargs);
	lunatik_unlock(runtime);
}

/***
* Creates and starts a new kernel thread to run a Lua task.
* The runtime must be sleepable; the script it loaded must return a function,
* which becomes the thread body, called with the objects given here. A thread a
* netdevice callback would stop is stopped off RTNL instead: from the script body,
* a later resume or another thread. The thread holds a reference to the runtime until
* `stop` releases it or the thread is collected, even once its body has returned.
* @function run
* @tparam runtime runtime A sleepable Lunatik runtime whose script returns a function.
* @tparam string name A descriptive name for the kernel thread.
* @param ... Lunatik objects passed to the thread body.
* @treturn thread the thread, which this call does not keep: dropping it stops nothing, the
*   thread runs until its body returns or `stop`, and once the handle is collected nothing can
*   stop it.
* @raise "not allowed while the runtime closes" from a finalizer that runs at its close; "not
*   allowed before the runtime is armed" from a script body; "IRQ runtime cannot spawn threads" for
*   a softirq or hardirq runtime; "stopped runtime"; "invalid object" or "cannot share SINGLE
*   object" for a value passed to the body; "couldn't pass the thread arguments"; the kernel's
*   errno if it cannot create the thread; "not allowed from the runtime itself" from under the
*   runtime's own lock, the contexts `runtime:stop` names, where passing the arguments would wait
*   on it; "EINTR" if the stop of the calling kernel thread, or a fatal signal to any other task,
*   ends its wait for the runtime's lock.
* @see lunatik.runtime
* @within thread
*/
static int luathread_run(lua_State *L)
{
	lunatik_checkclosing(L);
	if (!lunatik_isready(lunatik_toruntime(L)))
		luaL_error(L, LUNATIK_ERR_UNARMED);
	lunatik_object_t *runtime = lunatik_checkobjectclass(L, 1, &lunatik_class);
	luaL_argcheck(L, !lunatik_isirq(runtime->opt), 1, "IRQ runtime cannot spawn threads");
	lunatik_checkowner(L, runtime); /* the arguments cross under its lock */
	const char *name = luaL_checkstring(L, 2);
	int nargs = lua_gettop(L) - LUATHREAD_ARGIX + 1;

	luathread_checkargs(L, nargs);

	lunatik_object_t *object = luathread_new(L);
	luathread_t *thread = object->private;

	luathread_pushargs(L, runtime, nargs);
	thread->nargs = nargs;

	struct task_struct *task = kthread_create(luathread_func, object, "%s", name);
	if (IS_ERR(task)) {
		luathread_popargs(runtime, nargs);
		lunatik_throw(L, PTR_ERR(task));
	}

	lunatik_getobject(object);
	lunatik_getobject(runtime);
	thread->runtime = runtime;
	thread->task = task;
	get_task_struct(task); /* kthread_stop reads the task after the body returned */
	wake_up_process(task);

	return 1; /* object */
}

LUNATIK_CLASSES(thread, &luathread_class);
LUNATIK_NEWLIB(thread, luathread_lib, luathread_classes);

static int __init luathread_init(void)
{
	return 0;
}

static void __exit luathread_exit(void)
{
}

module_init(luathread_init);
module_exit(luathread_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

