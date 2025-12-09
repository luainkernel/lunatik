/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
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
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/completion.h>
#include <linux/sched.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

LUNATIK_OBJECTCHECKER(luacompletion_check, struct completion *);

/***
* Signals a completion.
* This wakes up one task waiting on this completion object.
* Corresponds to the kernel's `complete()` function.
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
* @treturn boolean `true` if the completion was signaled successfully before timeout or interruption.
* @treturn nil,string `nil` and an error message if the wait did not complete successfully. The message will be one of:
*   - `"timeout"`: The specified timeout elapsed.
*   - `"interrupt"`: The waiting task was interrupted by a signal (e.g., `thread.stop()`).
*   If the wait fails for other kernel internal reasons, the C code might push `"unknown"`, though typical documented returns are for timeout and interrupt.
*   - `"unknown"`: An unexpected error occurred during the wait.
* @usage
*   -- Assuming 'c' is a completion object
*   local success, err_msg = c:wait(1000) -- Wait for up to 1 second
*   if success then
*     print("Completion received!")
*   else
*     print("Wait failed: " .. err_msg)
*   end
* @see completion.new
*/
static int luacompletion_wait(lua_State *L)
{
	struct completion *completion = luacompletion_check(L, 1);
	lua_Integer timeout = luaL_optinteger(L, 2, MAX_SCHEDULE_TIMEOUT);
	unsigned long timeout_jiffies = msecs_to_jiffies((unsigned long)timeout);
	long ret;

	lunatik_checkruntime(L, true);
	ret = wait_for_completion_interruptible_timeout(completion, timeout_jiffies);
	if (ret > 0) {
		lua_pushboolean(L, true);
		return 1;		
	}

	lua_pushnil(L);
	switch (ret) {
	case 0:
		lua_pushliteral(L, "timeout");
		break;
	case -ERESTARTSYS:
		lua_pushliteral(L, "interrupt");
		break;
	default:
		lua_pushliteral(L, "unknown");
		break;
	}
	return 2;
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
	.flags = false,
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
	lunatik_object_t *object = lunatik_newobject(L, &luacompletion_class, sizeof(struct completion));
	struct completion *completion = (struct completion *)object->private;

	init_completion(completion);
	return 1;
}

LUNATIK_NEWLIB(completion, luacompletion_lib, &luacompletion_class, NULL);

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
MODULE_AUTHOR("Savio Sena <savio.sena@gmail.com>");

