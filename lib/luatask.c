/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux task interface.
* @module task
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/kthread.h>

#include "luatask.h"

LUNATIK_PRIVATECHECKER(luatask_check, struct task_struct *,
	luaL_argcheck(L, private != NULL, ix, "task is not set");
);

/***
* Returns the command name (comm) of the task, i.e., the executable.
* This is truncated to TASK_COMM_LEN (16) characters by the kernel.
* @function comm
* @treturn string command name of the task
*/
static int luatask_comm(lua_State *L)
{
	struct task_struct *task = luatask_check(L, 1);
	lua_pushstring(L, task->comm);
	return 1;
}

/***
* Returns the process ID (PID) of the task.
* For threads, this is the thread ID (TID) unique to each thread.
* @function pid
* @treturn integer pid of the task
*/
static int luatask_pid(lua_State *L)
{
	struct task_struct *task = luatask_check(L, 1);
	lua_pushinteger(L, task->pid);
	return 1;
}

/***
* Returns the thread group ID (TGID) of the task.
* For the main thread, TGID equals PID. For other threads in the group,
* TGID is the PID of the main thread.
* @function tgid
* @treturn integer tgid of the task
*/
static int luatask_tgid(lua_State *L)
{
	struct task_struct *task = luatask_check(L, 1);
	lua_pushinteger(L, task->tgid);
	return 1;
}

/***
* Returns the dynamic priority of the task.
* Ranges from 0 (highest) to 139 (lowest); normal tasks are 100-139,
* real-time tasks are 0-99.
* @function prio
* @treturn integer priority of the task
*/
static int luatask_prio(lua_State *L)
{
	struct task_struct *task = luatask_check(L, 1);
	lua_pushinteger(L, task->prio);
	return 1;
}

/***
* Returns whether the task is currently running on a CPU.
* Only available on SMP systems.
* @function cpu
* @treturn integer 1 if a task is actively occupying a CPU core, else 0.
*/
#ifdef CONFIG_SMP
static int luatask_cpu(lua_State *L)
{
	struct task_struct *task = luatask_check(L, 1);
	lua_pushinteger(L, task->on_cpu);
	return 1;
}
#endif

/***
* Gets an object representing the current kernel task.
* @function current
* @treturn task task object for the current task.
* @usage
* local task = require("task")
* local t = task.current()
* print(t:pid(), t:comm())
*/
static int luatask_current(lua_State *L)
{
	lunatik_object_t *object = luatask_new(L, current);
	lunatik_pushobject(L, object);
	return 1;
}

static void luatask_release(void *private)
{
	struct task_struct *task = (struct task_struct *)private;
	if (task) {
		put_task_struct(task);
		task = NULL;
	}
}

static const luaL_Reg luatask_lib[] = {
	{"current", luatask_current},
	{NULL, NULL}
};

static const luaL_Reg luatask_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"comm", luatask_comm},
	{"pid",  luatask_pid},
	{"tgid", luatask_tgid},
	{"prio", luatask_prio},
#ifdef CONFIG_SMP
	{"cpu",  luatask_cpu},
#endif
	{NULL, NULL}
};

LUNATIK_OPENER(task);
static const lunatik_class_t luatask_class = {
	.name    = "task",
	.methods = luatask_mt,
	.release = luatask_release,
	.opener = luaopen_task,
	.opt = LUNATIK_OPT_SOFTIRQ,
};

lunatik_object_t *luatask_new(lua_State *L, struct task_struct *task)
{
	lunatik_require(L, &luatask_class);
	lunatik_object_t *object = lunatik_newobject(L, &luatask_class, sizeof(struct task_struct *), LUNATIK_OPT_NONE);
	if (task != NULL) {
		get_task_struct(task);
	}
	object->private = task;
	lunatik_getobject(object);
	lua_pop(L, 1);
	return object;
}
EXPORT_SYMBOL(luatask_new);

int luatask_stop(lunatik_object_t *object)
{
	struct task_struct *task;
	if (!object)
		return -ESRCH;
	task = (struct task_struct *)object->private;
	if (!task)
		return -ESRCH;
	return kthread_stop(task);
}
EXPORT_SYMBOL(luatask_stop);

lunatik_object_t *luatask_run(lua_State *L, int (*threadfn)(void *data), void *data, const char *name)
{
	struct task_struct *task;

	task = kthread_run(threadfn, data, name);
	if (IS_ERR(task))
		return ERR_CAST(task);

	return luatask_new(L, task);
}
EXPORT_SYMBOL(luatask_run);

LUNATIK_CLASSES(task, &luatask_class);
LUNATIK_NEWLIB(task, luatask_lib, luatask_classes);

static int __init luatask_init(void)
{
	return 0;
}

static void __exit luatask_exit(void)
{
}

module_init(luatask_init);
module_exit(luatask_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>");

