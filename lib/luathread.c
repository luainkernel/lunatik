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
	lunatik_object_t *task;
	lunatik_object_t *runtime;
} luathread_t;

static int luathread_run(lua_State *L);

static int luathread_resume(lua_State *L, luathread_t *thread)
{
	int nresults;
	int status = lua_resume(L, NULL, 0, &nresults);
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
	lunatik_putobject(thread->task);
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
	lunatik_object_t *task = thread->task;

	if (runtime == NULL)
		pr_warn("[%p] thread wasn't created by us\n", thread);
	else if (task != NULL) {
		int result = luatask_stop(task);

		if (result == -EINTR) {
			thread->task = NULL;
			lunatik_putobject(task);
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
* Retrieves information about the kernel task associated with the thread.
* @function task
* @tparam thread self thread object.
* @treturn table A table with fields: `cpu` (SMP only), `command`, `pid`, `tgid`.
* @usage
* local info = my_thread:task()
*/
static int luathread_task(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luathread_t *thread = (luathread_t *)object->private;

	if (!thread->task) {
		lua_pushnil(L);
		return 1;
	}
	lunatik_getobject(thread->task);
	lunatik_pushobject(L, thread->task);
	return 1;
}

static const luaL_Reg luathread_lib[] = {
	{"run", luathread_run},
	{"shouldstop", luathread_shouldstop},
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

/***
* Creates and starts a new kernel thread to run a Lua task.
* The runtime must be sleepable; the script it loaded must return a function,
* which becomes the thread body.
* @function run
* @tparam runtime runtime A sleepable Lunatik runtime whose script returns a function.
* @tparam string name A descriptive name for the kernel thread.
* @treturn thread A new thread object.
* @raise Error if the runtime is not sleepable or if thread creation fails.
* @see lunatik.runtime
*/
static int luathread_run(lua_State *L)
{
	luaL_argcheck(L, lunatik_isready(lunatik_toruntime(L)), 1, "not allowed during module load");
	lunatik_object_t *runtime = lunatik_checkobject(L, 1);
	luaL_argcheck(L, !lunatik_isirq(runtime->opt), 1, "IRQ runtime cannot spawn threads");
	const char *name = luaL_checkstring(L, 2);
	lunatik_object_t *object = luathread_new(L);
	luathread_t *thread = object->private;

	lunatik_getobject(object);
	lunatik_getobject(runtime);
	thread->runtime = runtime;

	thread->task = luatask_run(L, luathread_func, object, name);
	if (IS_ERR(thread->task))
		luaL_error(L, "failed to create a new thread");

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

