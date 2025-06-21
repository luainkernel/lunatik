/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Kernel thread primitives.
* This library provides support for creating and managing kernel threads from Lua.
* It allows running Lua scripts, encapsulated in Lunatik runtime environments,
* within dedicated kernel threads.
* @module thread
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kthread.h>
#include <linux/sched/signal.h> 
#include <linux/signal.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

/***
* Represents a kernel thread object.
* This is a userdata object returned by `thread.run()` or `thread.current()`.
* It encapsulates a kernel `struct task_struct` and, if created by `thread.run()`,
* the Lunatik runtime environment associated with the thread's Lua task.
* @type thread
*/

typedef struct luathread_s {
	struct task_struct *task;
	lunatik_object_t *runtime;
} luathread_t;

LUNATIK_PRIVATECHECKER(luathread_check, luathread_t *);

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
	lua_pop(L, nresults); /* ignore results */
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
* This function should be called periodically within a thread's main loop
* to allow for graceful termination when `thrd:stop()` is invoked.
* It wraps the kernel's `kthread_should_stop()`.
* @function shouldstop
* @treturn boolean `true` if the thread should stop, `false` otherwise.
* @usage
* -- Inside a function returned by a script passed to thread.run():
* while not thread.shouldstop() do
*   -- do work
*   linux.schedule(100) -- example: yield/sleep
* end
* print("Thread is stopping.")
* @see stop
* @within thread
*/
static int luathread_shouldstop(lua_State *L)
{
	lua_pushboolean(L, (int)kthread_should_stop());
	return 1;
}

/***
* Stops a running kernel thread.
* Signals the specified thread to stop and waits for it to exit.
* This calls `kthread_stop()` on the underlying kernel thread.
* @function stop
* @tparam thread self The thread object to stop.
* @treturn nil
* @usage
* -- Assuming 'my_thread' is an object returned by thread.run()
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
* @treturn table A table containing task information with the following fields:
*   @tfield[opt] integer cpu The CPU number the task is currently running on (if CONFIG_SMP is enabled).
*   @tfield string command The command name of the task.
*   @tfield integer pid The process ID (PID) of the task.
*   @tfield integer tgid The thread group ID (TGID) of the task.
* @usage
* local t_info = my_thread:task()
* print("Thread PID:", t_info.pid)
* print("Command:", t_info.command)
* if t_info.cpu then print("Running on CPU:", t_info.cpu) end
*/
static int luathread_task(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luathread_t *thread = (luathread_t *)object->private;
	struct task_struct *task = thread->task;
	int nrec = 4; /* number of elements */
	int table;

	lua_createtable(L, 0, nrec);
	table = lua_gettop(L);

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

/***
* Allows the current kernel thread to handle a specific signal.
* This function enables the thread to receive and process the specified signal by unblocking it at the kernel level.
* @function allow
* @tparam integer signum The signal number to allow (e.g., 15 for SIGTERM)
* @treturn nil
* @usage
* local t = thread.current()
* t:allow(15)  -- Allow SIGTERM
*/

static int luathread_allow(lua_State *L)
{
 	int signum = luaL_checkinteger(L, 2);
 	allow_signal(signum);
	
 	return 0;
}


/***
 * Sends a signal to the kernel thread represented by this thread object.
 * This function attempts to deliver the specified signal to the kernel thread associated with the given lua thread object. 
 * @function send
 * @tparam integer signum The signal number to send (e.g., 15).
 * @treturn nil
 * @raise If the thread's kernel task has exited or does not exist, or if signal delivery fails.
 * @usage
 * -- Assuming t is a running thread
 * t:send(15) -- Send SIGTERM to the worker thread
 */
static int luathread_send_signal(lua_State *L)
{
    luathread_t *thread = luathread_check(L, 1);

    if (!thread->task)
        return luaL_error(L, "thread task is NULL (might have exited)");

    int signum = luaL_checkinteger(L, 2);

    if (send_sig(signum, thread->task, 0))
        return luaL_error(L, "send_sig failed for signal %d", signum);

    return 0;
}
static int luathread_send(lua_State *L)
{
	luathread_t *thread = luathread_check(L,1);
   
    	if (!thread->task)
        	return luaL_error(L, "thread task is NULL (might have exited)");

	int signum = luaL_checkinteger(L, 2);

    	if (send_sig(signum, thread->task, 0))
        	return luaL_error(L, "send_sig failed for signal %d", signum);
 	
	return 0;
}

static int luathread_pending(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
 	luathread_t *thread = (luathread_t *)object->private;
	
	struct task_struct *task = thread->task;
	if (!task)
 		return luaL_error(L, "thread task is NULL");
 	lua_pushboolean(L, signal_pending(task));
	 
	return 1;
}

static const luaL_Reg luathread_lib[] = {
	{"run", luathread_run},
	{"shouldstop", luathread_shouldstop},
	{"current", luathread_current},
	{NULL, NULL}
};

static const luaL_Reg luathread_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"stop", luathread_stop},
	{"task", luathread_task},
        {"allow", luathread_allow},
        {"send", luathread_send},
        {"pending", luathread_pending},

	{NULL, NULL}
};

static const lunatik_class_t luathread_class = {
	.name = "thread",
	.methods = luathread_mt,
	.sleep = true,
};

#define luathread_new(L)	(lunatik_newobject((L), &luathread_class, sizeof(luathread_t)))

/***
* Creates and starts a new kernel thread to run a Lua task.
* The Lua task is defined by a function returned from the script loaded into the provided `runtime` environment.
* The new thread begins execution by resuming this function.
* The runtime environment must be sleepable.
* @function run
* @tparam runtime runtime A Lunatik runtime object. The script associated with this runtime
*   (e.g., loaded via `lunatik.runtime("path/to/script.lua")`) must return a function.
*   This function will be executed in the new kernel thread.
* @tparam string name A descriptive name for the kernel thread (e.g., as shown in `ps` or `top`).
* @treturn thread A new thread object representing the created kernel thread.
* @raise Error if the runtime is not sleepable, if memory allocation fails, or if `kthread_run` fails.
* @usage
* -- main_script.lua
* local lunatik = require("lunatik")
* local thread = require("thread")
* -- Assume "worker_script.lua" returns a function: function() print("worker running") while not thread.shouldstop() do linux.schedule(1000) end print("worker stopped") end
* local worker_rt = lunatik.runtime("worker_script.lua")
* local new_thread = thread.run(worker_rt, "my_lua_worker")
* @see lunatik.runtime
* @within thread
*/
static int luathread_run(lua_State *L)
{
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
* Note: If the current task was not created by `thread.run()`, the returned
* thread object will not have an associated Lunatik runtime.
* @function current
* @treturn thread A thread object for the current task.
* @usage
* local current_task_as_thread = thread.current()
* @within thread
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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");
