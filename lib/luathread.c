/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Kernel thread primitives.
* @module thread
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kthread.h>

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
static int luathread_current(lua_State *L);
static void luathread_popargs(lunatik_object_t *runtime, int nargs);

static int luathread_resume(lua_State *L, luathread_t *thread)
{
	int nresults;
	int status = lua_resume(L, NULL, thread->nargs, &nresults);
	if (status != LUA_OK && status != LUA_YIELD) {
		pr_err("[%p] %s\n", thread, lua_tostring(L, -1));
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
	int ret, locked = 0;

	lunatik_run(thread->runtime, luathread_resume, ret, thread);

	while (!kthread_should_stop())
		if ((locked = lunatik_trylock(object)))
			break;

	thread->task = NULL;

	if (locked)
		lunatik_unlock(object);

	lunatik_putobject(thread->runtime);
	lunatik_putobject(object);
	return ret;
}

/***
* Checks if the current thread has been signaled to stop.
* @function shouldstop
* @treturn boolean `true` if the thread should stop, `false` otherwise.
* @usage
* while not thread.shouldstop() do
*   linux.schedule(100)
* end
* @see stop
*/
static int luathread_shouldstop(lua_State *L)
{
	lua_pushboolean(L, (current->flags & PF_KTHREAD) ? (int)kthread_should_stop() : 0);
	return 1;
}

/***
* Stops a running kernel thread.
* Signals the thread to stop and waits for it to exit.
* @function stop
* @tparam thread self thread object to stop.
* @treturn nil
* @usage
* my_thread:stop()
*/
static int luathread_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luathread_t *thread = (luathread_t *)object->private;
	lunatik_object_t *runtime = thread->runtime;
	struct task_struct *task = thread->task;

	if (runtime == NULL)
		pr_warn("[%p] thread wasn't created by us\n", thread);
	else if (task != NULL) {
		int result = kthread_stop(task);

		if (result == -EINTR) {
			thread->task = NULL;
			luathread_popargs(runtime, thread->nargs);
			lunatik_putobject(thread->runtime);
			lunatik_putobject(object);
			pr_warn("[%p] thread has never run\n", thread);
		}
		else if (result == -ENOEXEC)
			pr_warn("[%p] thread has failed to execute\n", thread);
	}
	else
		pr_warn("[%p] thread has already stopped\n", thread);
	return 0;
}

/***
* Returns a task object for the kernel task associated with the thread.
* Once the thread has exited the object has no task and its methods raise.
* @function task
* @tparam thread self thread object.
* @treturn task
* @usage
* local t = my_thread:task()
* print(t:pid(), t:comm())
*/
static int luathread_task(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luathread_t *thread = (luathread_t *)object->private;

	luatask_new(L, thread->task);
	return 1;
}

static const luaL_Reg luathread_lib[] = {
	{"run", luathread_run},
	{"shouldstop", luathread_shouldstop},
	{"current", luathread_current},
	{NULL, NULL}
};

static const luaL_Reg luathread_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"stop", luathread_stop},
	{"task", luathread_task},
	{NULL, NULL}
};

LUNATIK_OPENER(thread);
static const lunatik_class_t luathread_class = {
	.name = "thread",
	.methods = luathread_mt,
	.opener = luaopen_thread,
	.opt = LUNATIK_OPT_MONITOR,
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

	lunatik_lock(runtime);
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
* which becomes the thread body, called with the objects given here.
* @function run
* @tparam runtime runtime A sleepable Lunatik runtime whose script returns a function.
* @tparam string name A descriptive name for the kernel thread.
* @param ... Lunatik objects passed to the thread body.
* @treturn thread A new thread object.
* @raise Error if called during module load, if the runtime is not sleepable or has been stopped,
*   if a value passed to the body is not a Lunatik object or is a `SINGLE` one, if the arguments
*   couldn't be passed, or if thread creation fails.
* @see lunatik.runtime
*/
static int luathread_run(lua_State *L)
{
	luaL_argcheck(L, lunatik_isready(lunatik_toruntime(L)), 1, "not allowed during module load");
	lunatik_object_t *runtime = lunatik_checkobjectclass(L, 1, &lunatik_class);
	luaL_argcheck(L, !lunatik_isirq(runtime->opt), 1, "IRQ runtime cannot spawn threads");
	const char *name = luaL_checkstring(L, 2);
	int nargs = lua_gettop(L) - LUATHREAD_ARGIX + 1;

	luathread_checkargs(L, nargs);

	lunatik_object_t *object = luathread_new(L);
	luathread_t *thread = object->private;

	luathread_pushargs(L, runtime, nargs);
	thread->nargs = nargs;

	lunatik_getobject(object);
	lunatik_getobject(runtime);
	thread->runtime = runtime;

	thread->task = kthread_run(luathread_func, object, name);
	if (IS_ERR(thread->task)) {
		luathread_popargs(runtime, nargs);
		lunatik_putobject(runtime);
		lunatik_putobject(object);
		luaL_error(L, "failed to create a new thread");
	}

	return 1; /* object */
}

/***
* Gets a thread object representing the current kernel task.
* If the current task was not created by `thread.run()`, the returned
* object will not have an associated Lunatik runtime.
* @function current
* @treturn thread A thread object for the current task.
* @usage
* local t = thread.current()
*/
static int luathread_current(lua_State *L)
{
	lunatik_object_t *object = luathread_new(L);
	luathread_t *thread = object->private;

	thread->runtime = NULL;
	thread->task = current;
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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

