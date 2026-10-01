/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua bindings for kernel completion mechanisms.
* This library allows Lua scripts to create, signal, and wait on
* kernel completion objects.
*
* Task completion is a synchronization mechanism used to coordinate the
* execution of multiple threads. It allows threads to wait for a specific
* event to occur before proceeding, ensuring certain tasks are complete.
*
* @module completion
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/completion.h>
#include <linux/sched.h>

#include <lunatik.h>

static const lunatik_class_t luacompletion_class;

LUNATIK_PRIVATECHECKER(luacompletion_check, struct completion *, &luacompletion_class);

/***
* Represents a kernel completion object.
* This is a userdata object returned by `completion.new()`, wrapping a
* `struct completion` used to wait for and signal an event.
* @type completion
*/

/***
* Signals a completion.
* This wakes up one task waiting on this completion object.
* Corresponds to the kernel's `complete()` function. It may be called from any runtime.
* @function complete
* @treturn nil
* @usage
*   -- Assuming 'c' is a completion object returned by completion.new()
*   c:complete()
* @see completion.new
*/
static int luacompletion_complete(lua_State *L)
{
	struct completion *completion = luacompletion_check(L, 1);

	complete(completion);
	return 0;
}

/***
* Waits for a completion to be signaled.
* This function will block the current Lua runtime until the completion
* is signaled, an optional timeout occurs, or the wait is interrupted.
* The Lunatik runtime invoking this method must be sleepable.
* Corresponds to the kernel's `wait_for_completion_interruptible_timeout()`.
*
* @function wait
* @tparam[opt] integer timeout Optional timeout in milliseconds. If omitted or set to `MAX_SCHEDULE_TIMEOUT` (a large kernel-defined constant), waits indefinitely.
* @treturn boolean `true` if the completion was signaled, `false` if the timeout elapsed first.
* @raise `ERESTARTSYS` when a signal or the stop of the thread that waits interrupts the wait;
*   "runtime context mismatch" from a softirq or hardirq runtime, its script body included;
*   "not allowed while the runtime closes" from a finalizer that runs at its close
* @usage
*   -- Assuming 'c' is a completion object
*   if c:wait(1000) then -- Wait for up to 1 second
*     print("Completion received!")
*   else
*     print("Timed out")
*   end
* @see completion.new
*/
static int luacompletion_wait(lua_State *L)
{
	struct completion *completion = luacompletion_check(L, 1);
	lua_Integer timeout = luaL_optinteger(L, 2, MAX_SCHEDULE_TIMEOUT);
	long ret;

	lunatik_checkruntime(L, luacompletion_class.name, LUNATIK_OPT_NONE);
	unsigned long timeout_jiffies = msecs_to_jiffies((unsigned long)timeout);
	lunatik_tryret(L, ret, wait_for_completion_interruptible_timeout, completion, timeout_jiffies);
	lua_pushboolean(L, ret > 0);
	return 1;
}

static int luacompletion_new(lua_State *L);

static const luaL_Reg luacompletion_lib[] = {
	{"new", luacompletion_new},
	{NULL, NULL}
};

static const luaL_Reg luacompletion_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"complete", luacompletion_complete},
	{"wait", luacompletion_wait},
	{NULL, NULL}
};

static const lunatik_class_t luacompletion_class = {
	.name = "completion",
	.methods = luacompletion_mt,
	.opt = LUNATIK_OPT_SOFTIRQ,
	.owner = THIS_MODULE,
};

/***
* Creates a new kernel completion object.
* Initializes a `struct completion` and returns it wrapped as a Lua userdata
* object of type `completion`.
* @function new
* @treturn completion A new completion object.
* @usage
*   local c = completion.new()
* @within completion
*/
static int luacompletion_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luacompletion_class, sizeof(struct completion), LUNATIK_OPT_NONE);
	struct completion *completion = (struct completion *)object->private;

	init_completion(completion);
	return 1;
}

LUNATIK_CLASSES(completion, &luacompletion_class);
LUNATIK_NEWLIB(completion, luacompletion_lib, luacompletion_classes);

static int __init luacompletion_init(void)
{
	return 0;
}

static void __exit luacompletion_exit(void)
{
}

module_init(luacompletion_init);
module_exit(luacompletion_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Savio Sena <savio.sena@gmail.com>");

