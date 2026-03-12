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

/***
* Represents a kernel thread object.
* @type thread
*/

typedef struct luathread_s {
	struct task_struct *task;
	lunatik_object_t *runtime;
} luathread_t;

static int luathread_run(lua_State *L);
static int luathread_current(lua_State *L);

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
* @tparam thread self The thread object to stop.
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
* @tparam thread self The thread object.
* @treturn table A table with fields: `cpu` (SMP only), `command`, `pid`, `tgid`.
* @usage
* local info = my_thread:task()
*/
static int luathread_task(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luathread_t *thread = (luathread_t *)object->private;
	struct task_struct *task = thread->task;

	lua_createtable(L, 0, 4);
	int table = lua_gettop(L);

#ifdef CONFIG_SMP
	lua_pushinteger(L, task->on_cpu);
	lua_setfield(L, table, "cpu");
#endif

	lua_pushstring(L, task->comm);
	lua_setfield(L, table, "command");

	lua_pushinteger(L, task->pid);
	lua_setfield(L, table, "pid");

	lua_pushinteger(L, task->tgid);
	lua_setfield(L, table, "tgid");
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

static const lunatik_class_t luathread_class = {
	.name = "thread",
	.methods = luathread_mt,
	.sleep = true,
	.shared = true,
};

#define luathread_new(L)	(lunatik_newobject((L), &luathread_class, sizeof(luathread_t), true, true))

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
	luaL_argcheck(L, lunatik_isready(L), 1, "not allowed during module load");
	lunatik_object_t *runtime = lunatik_checkobject(L, 1);
	luaL_argcheck(L, runtime->sleep, 1, "cannot use non-sleepable runtime in this context");
	const char *name = luaL_checkstring(L, 2);
	lunatik_object_t *object = luathread_new(L);
	luathread_t *thread = object->private;

	lunatik_getobject(object);
	lunatik_getobject(runtime);
	thread->runtime = runtime;

	thread->task = kthread_run(luathread_func, object, name);
	if (IS_ERR(thread->task))
		luaL_error(L, "failed to create a new thread");

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

LUNATIK_NEWLIB(thread, luathread_lib, &luathread_class, NULL);

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

