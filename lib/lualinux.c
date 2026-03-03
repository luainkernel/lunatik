/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Various Linux kernel facilities.
* This library includes functions for random number generation, task scheduling,
* time retrieval, kernel symbol lookup, network interface information,
* access to kernel constants like file modes, task states, and error numbers.
*
* @module linux
*/

#include <linux/random.h>
#include <linux/stat.h>
#include <linux/sched.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/netdevice.h>

#include <lunatik.h>

/***
* Generates pseudo-random integers.
* Mimics the behavior of Lua's `math.random` but uses kernel's random number
* generation facilities (`get_random_u32` or `get_random_u64`).
*
* @function random
* @tparam[opt] integer m Lower bound of the range. If only one argument `n` is provided, `m` defaults to 1.
* @tparam[opt] integer n Upper bound of the range.
* @treturn integer A pseudo-random integer.
*   - If called without arguments, returns an integer with all bits pseudo-random.
*   - If called with one integer `n`, returns a pseudo-random integer in the range `[1, n]`.
*   - If called with two integers `m` and `n`, returns a pseudo-random integer in the range `[m, n]`.
* @raise Error if `m > n` or if the interval is too large.
* @usage
*   local r1 = linux.random()       -- Full range random integer
*   local r2 = linux.random(100)    -- Random integer between 1 and 100
*   local r3 = linux.random(50, 60) -- Random integer between 50 and 60
*/
/* based on math_random() @ lua/lmathlib.c */
static int lualinux_random(lua_State *L)
{
	lua_Integer low, up, rand;

	switch (lua_gettop(L)) {  /* check number of arguments */
	case 0: {  /* no arguments */
		lua_pushinteger(L, (lua_Integer)get_random_u64());
		return 1;
	}
	case 1: {  /* only upper limit */
		low = 1;
		up = luaL_checkinteger(L, 1);
		break;
	}
	case 2: {  /* lower and upper limits */
		low = luaL_checkinteger(L, 1);
		up = luaL_checkinteger(L, 2);
		break;
	}
	default:
		return luaL_error(L, "wrong number of arguments");
	}

	/* random integer in the interval [low, up] */
	luaL_argcheck(L, low <= up, 1, "interval is empty");
	luaL_argcheck(L, low >= 0 || up <= LUA_MAXINTEGER + low, 1, "interval too large");

	rand = low + ((lua_Integer)get_random_u64()) % (up - low + 1);
	lua_pushinteger(L, rand);
	return 1;
}

/***
* Puts the current task to sleep.
* Sets the current task's state and schedules it out until a timeout occurs
* or it is woken up.
*
* @function schedule
* @tparam[opt] integer timeout Duration in milliseconds to sleep.
* Defaults to `MAX_SCHEDULE_TIMEOUT` (effectively indefinite sleep until woken).
* @tparam[opt] integer state The task state to set before sleeping.
* See `linux.task` for possible values. Defaults to `linux.task.INTERRUPTIBLE`.
* @treturn integer The remaining time in milliseconds
* if the sleep was interrupted before the full timeout, or 0 if the full timeout elapsed.
* @raise Error if an invalid task state is provided.
* @see linux.task
* @usage
*   linux.schedule(1000) -- Sleep for 1 second (interruptible)
*   linux.schedule(500, linux.task.UNINTERRUPTIBLE) -- Sleep for 0.5 seconds (uninterruptible)
*/
static int lualinux_schedule(lua_State *L)
{
	lua_Integer timeout = luaL_optinteger(L, 1, MAX_SCHEDULE_TIMEOUT);
	lua_Integer state = luaL_optinteger(L, 2, TASK_INTERRUPTIBLE);

	if (timeout != MAX_SCHEDULE_TIMEOUT)
		timeout = msecs_to_jiffies(timeout);

	luaL_argcheck(L, state == TASK_INTERRUPTIBLE || state == TASK_UNINTERRUPTIBLE ||
		state == TASK_KILLABLE || state == TASK_IDLE, 2, "invalid task state");
	__set_current_state(state);

	lua_pushinteger(L, jiffies_to_msecs(schedule_timeout(timeout)));
	return 1;
}

/***
* Controls kernel tracing.
* Turns kernel tracing on or off via `tracing_on()` and `tracing_off()`.
*
* @function tracing
* @tparam[opt] boolean enable If `true`, turns tracing on. If `false`, turns tracing off.
* If omitted, does not change the state.
* @treturn boolean The current state of kernel tracing (`true` if on, `false` if off) *after* any change.
* @usage
*   local was_tracing = linux.tracing(true) -- Enable tracing
*   if was_tracing then print("Tracing is now on") end
*   local current_state = linux.tracing()   -- Get current state
*   linux.tracing(false)                    -- Disable tracing
*/
static int lualinux_tracing(lua_State *L)
{
	if (lua_gettop(L) == 0)
		goto out;

	if (lua_toboolean(L, 1))
		tracing_on();
	else
		tracing_off();
out:
	lua_pushboolean(L, tracing_is_on());
	return 1;
}

/***
* Gets the current real time.
*
* @function time
* @treturn integer The current time in nanoseconds since the epoch (from `ktime_get_real_ns`).
*/
static int lualinux_time(lua_State *L)
{
	lua_pushinteger(L, (lua_Integer)ktime_get_real_ns());
	return 1;
}

/***
* Calculates the difference between two timestamps.
*
* @function difftime
* @tparam integer t2 The later timestamp (e.g., from `linux.time()`).
* @tparam integer t1 The earlier timestamp (e.g., from `linux.time()`).
* @treturn integer The difference `t2 - t1` in nanoseconds.
*/
static int lualinux_difftime(lua_State *L)
{
	u64 t2 = (u64) luaL_checkinteger(L, 1);
	u64 t1 = (u64) luaL_checkinteger(L, 2);
	lua_pushinteger(L, (lua_Integer)(t2 - t1));
	return 1;
}

/***
* Looks up a kernel symbol by name.
* Uses `kallsyms_lookup_name` (potentially via kprobes) to find the address
* of a kernel symbol.
*
* @function lookup
* @tparam string symbol_name The name of the kernel symbol to look up.
* @treturn lightuserdata The address of the symbol if found, otherwise `nil` (represented as a NULL lightuserdata).
* @usage
*   local addr = linux.lookup("jiffies")
*   if addr then print("Address of jiffies:", addr) end
*/
static int lualinux_lookup(lua_State *L)
{
	const char *symbol = luaL_checkstring(L, 1);

	lua_pushlightuserdata(L, lunatik_lookup(symbol));
	return 1;
}

/***
* Gets the interface index for a network device name.
*
* @function ifindex
* @tparam string interface_name The name of the network interface (e.g., "eth0").
* @treturn integer The interface index.
* @raise Error if the device is not found.
* @usage
*   local index = linux.ifindex("lo")
*   print("Index of lo:", index)
*/
static int lualinux_ifindex(lua_State *L)
{
	const char *ifname = luaL_checkstring(L, 1);
	struct net_device *dev = dev_get_by_name(&init_net, ifname);

	luaL_argcheck(L, dev != NULL, 1, "device not found");
	lua_pushinteger(L, dev->ifindex);
	dev_put(dev);
	return 1;
}

/***
* Gets the HW address for the network interface index.
*
* @function ifaddr
* @tparam integer The interface index number.
* @treturn string The interface HW address.
* @raise Error if the device is not found.
* @usage
*   local addr = linux.ifaddr(index)
*   print(string.byte(addr,1,6))
*/
static int lualinux_ifaddr(lua_State *L)
{
	int ifindex = luaL_checkinteger(L, 1);
	luaL_Buffer B;
	char *addr = luaL_buffinitsize(L, &B, MAX_ADDR_LEN);
	struct net_device *dev = dev_get_by_index(&init_net, ifindex);

	luaL_argcheck(L, dev != NULL, 1, "device not found");
	size_t len = min_t(size_t, dev->addr_len, MAX_ADDR_LEN);
	memcpy(addr, dev->dev_addr, len);
	dev_put(dev);
	luaL_pushresultsize(&B, len);
	return 1;
}

/***
* Table of task state constants.
* Exports task state flags from `<linux/sched.h>`. These are used with
* `linux.schedule()`.
*
* @table task
*   @tfield integer INTERRUPTIBLE Task is waiting for a signal or a resource (sleeping), can be interrupted.
*   @tfield integer UNINTERRUPTIBLE Task is waiting (sleeping),
*   cannot be interrupted by signals (except fatal ones if KILLABLE is also implied by context).
*   @tfield integer KILLABLE Task is waiting (sleeping) like UNINTERRUPTIBLE, but can be interrupted by fatal signals.
*   @tfield integer IDLE Task is idle, similar to UNINTERRUPTIBLE but avoids loadavg accounting.
* @see linux.schedule
*/
static const lunatik_reg_t lualinux_task[] = {
	{"INTERRUPTIBLE", TASK_INTERRUPTIBLE},
	{"UNINTERRUPTIBLE", TASK_UNINTERRUPTIBLE},
	{"KILLABLE", TASK_KILLABLE},
	{"IDLE", TASK_IDLE},
	{NULL, 0}
};

/***
* Table of file mode constants.
* Exports file permission flags from `<linux/stat.h>`. These can be used, for
* example, with `device.new()` to set the mode of a character device.
*/
static const lunatik_reg_t lualinux_stat[] = {
	/* user */
	{"IRWXU", S_IRWXU},
	{"IRUSR", S_IRUSR},
	{"IWUSR", S_IWUSR},
	{"IXUSR", S_IXUSR},
	/* group */
	{"IRWXG", S_IRWXG},
	{"IRGRP", S_IRGRP},
	{"IWGRP", S_IWGRP},
	{"IXGRP", S_IXGRP},
	/* other */
	{"IRWXO", S_IRWXO},
	{"IROTH", S_IROTH},
	{"IWOTH", S_IWOTH},
	{"IXOTH", S_IXOTH},
	/* user, group, other */
	{"IRWXUGO", (S_IRWXU|S_IRWXG|S_IRWXO)},
	{"IALLUGO", (S_ISUID|S_ISGID|S_ISVTX|S_IRWXUGO)},
	{"IRUGO", (S_IRUSR|S_IRGRP|S_IROTH)},
	{"IWUGO", (S_IWUSR|S_IWGRP|S_IWOTH)},
	{"IXUGO", (S_IXUSR|S_IXGRP|S_IXOTH)},
	{NULL, 0}
};

/***
* Returns the symbolic name of a kernel error number.
* For example, it converts `2` to `"ENOENT"`.
*
* @function errname
* @tparam integer err The error number (e.g., 2).
* @treturn string The symbolic name of the error (e.g., "ENOENT").
* Returns "unknown" (or the error number as a string) if the name cannot be resolved.
* @usage
* local name = linux.errname(2)
* print("Error name:", name) -- "ENOENT"
*/
static int lualinux_errname(lua_State *L)
{
    int e = (int)luaL_checkinteger(L, 1);
    lunatik_pusherrname(L, e);
    return 1;
}

static const lunatik_namespace_t lualinux_flags[] = {
	{"stat", lualinux_stat},
	{"task", lualinux_task},
	{NULL, NULL}
};

static const luaL_Reg lualinux_lib[] = {
	{"random", lualinux_random},
	{"schedule", lualinux_schedule},
	{"tracing", lualinux_tracing},
	{"time", lualinux_time},
	{"difftime", lualinux_difftime},
	{"lookup", lualinux_lookup},
	{"ifindex", lualinux_ifindex},
	{"ifaddr", lualinux_ifaddr},
	{"errname", lualinux_errname},
	{NULL, NULL}
};

LUNATIK_NEWLIB(linux, lualinux_lib, NULL, lualinux_flags);

static int __init lualinux_init(void)
{
	return 0;
}

static void __exit lualinux_exit(void)
{
}

module_init(lualinux_init);
module_exit(lualinux_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

