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

typedef struct luacompletion_s {
	struct completion completion;
	lunatik_defer_t defer;
	atomic_t deferred;
} luacompletion_t;

static const lunatik_class_t luacompletion_class;

LUNATIK_PRIVATECHECKER(luacompletion_check, luacompletion_t *, &luacompletion_class);

/***
* Represents a kernel completion object.
* This is a userdata object returned by `completion.new()`, wrapping a
* `struct completion` used to wait for and signal an event.
* @type completion
*/

/***
* Signals a completion.
* This wakes up one task waiting on this completion object.
* Corresponds to the kernel's `complete()` function. It may be called from any runtime. With IRQs
* disabled, as in every callback of a hardirq runtime, a probe's handlers among them, the wakeup
* runs on a kernel worker after the call, once for each such call; with IRQs on, it runs in place.
* @function complete
* @treturn nil
* @usage
*   -- Assuming 'c' is a completion object returned by completion.new()
*   c:complete()
* @see completion.new
*/
static int luacompletion_complete(lua_State *L)
{
	luacompletion_t *completion = luacompletion_check(L, 1);

	if (irqs_disabled()) { /* the wakeup takes a runqueue lock this CPU may hold */
		atomic_inc(&completion->deferred);
		lunatik_defer(&completion->defer);
	}
	else
		complete(&completion->completion);
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
*   "runtime context mismatch" from a softirq or hardirq runtime, its script body included
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
	luacompletion_t *completion = luacompletion_check(L, 1);
	lua_Integer timeout = luaL_optinteger(L, 2, MAX_SCHEDULE_TIMEOUT);
	long ret;

	lunatik_checkcontext(L, luacompletion_class.name, LUNATIK_OPT_NONE);
	unsigned long timeout_jiffies = msecs_to_jiffies((unsigned long)timeout);
	lunatik_tryret(L, ret, wait_for_completion_interruptible_timeout, &completion->completion, timeout_jiffies);
	lua_pushboolean(L, ret > 0);
	return 1;
}

static void luacompletion_drain(struct work_struct *work)
{
	luacompletion_t *completion = container_of(work, luacompletion_t, defer.work);

	for (int deferred = atomic_xchg(&completion->deferred, 0); deferred > 0; deferred--)
		complete(&completion->completion);
}

static void luacompletion_release(void *private)
{
	luacompletion_t *completion = (luacompletion_t *)private;

	lunatik_syncdefer(&completion->defer);
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
	.release = luacompletion_release,
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
	lunatik_object_t *object = lunatik_newobject(L, &luacompletion_class, sizeof(luacompletion_t), LUNATIK_OPT_NONE);
	luacompletion_t *completion = (luacompletion_t *)object->private;

	init_completion(&completion->completion);
	lunatik_initdefer(&completion->defer, luacompletion_drain);
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

