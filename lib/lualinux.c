/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Various Linux kernel facilities.
* This library includes functions for random number generation, task scheduling,
* time retrieval, kernel symbol lookup, network interface information,
* byte order conversion, and access to kernel constants like file modes,
* task states, and error numbers.
*
* @module linux
*/

#include <linux/module.h>
#include <linux/random.h>
#include <linux/stat.h>
#include <linux/sched.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/netdevice.h>
#include <linux/byteorder/generic.h>
#include <linux/sched/signal.h>
#include <linux/pid.h> 

#include <lua.h>
#include <lauxlib.h>

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
#ifdef __LP64__
		lua_pushinteger(L, (lua_Integer)get_random_u64());
#else
		lua_pushinteger(L, (lua_Integer)get_random_u32());
#endif
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

	rand = low + get_random_u32() % (up - low + 1);
	lua_pushinteger(L, rand);
	return 1;
}

/***
* Puts the current task to sleep.
* Sets the current task's state and schedules it out until a timeout occurs
* or it is woken up.
*
* @function schedule
* @tparam[opt] integer timeout Duration in milliseconds to sleep. Defaults to `MAX_SCHEDULE_TIMEOUT` (effectively indefinite sleep until woken).
* @tparam[opt] integer state The task state to set before sleeping. See `linux.task` for possible values. Defaults to `linux.task.INTERRUPTIBLE`.
* @treturn integer The remaining time in milliseconds if the sleep was interrupted before the full timeout, or 0 if the full timeout elapsed.
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
* Kills a process by sending SIGKILL to pid.
* @function kill
* @tparam integer pid Process ID to kill.
* @treturn boolean `true` if successful.
* @raise Error if process not found or kill fails.
* @usage 
* linux.kill(1234) 
*/
static int lualinux_kill(lua_State *L)
{
    pid_t pid = (pid_t)luaL_checkinteger(L, 1);
    struct pid *pid_struct = find_get_pid(pid);

    luaL_argcheck(L, pid_struct != NULL, 1, "process not found");
    
    int ret = kill_pid(pid_struct, SIGKILL, 0);
    put_pid(pid_struct);
    
    if (ret) {
        return luaL_error(L, "kill failed with error %d", ret);
    }
    
    lua_pushboolean(L, true);
    return 1;
}

/***
* Controls kernel tracing.
* Turns kernel tracing on or off via `tracing_on()` and `tracing_off()`.
*
* @function tracing
* @tparam[opt] boolean enable If `true`, turns tracing on. If `false`, turns tracing off. If omitted, does not change the state.
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

#define LUALINUX_NEW_BYTESWAPPER(func, T) \
static int lualinux_##func(lua_State *L) \
{ \
	T x = (T)luaL_checkinteger(L, 1); \
	lua_pushinteger(L, (lua_Integer)func(x)); \
	return 1; \
}

LUALINUX_NEW_BYTESWAPPER(cpu_to_be16, uint32_t);
LUALINUX_NEW_BYTESWAPPER(cpu_to_be32, uint32_t);
LUALINUX_NEW_BYTESWAPPER(cpu_to_le16, uint32_t);
LUALINUX_NEW_BYTESWAPPER(cpu_to_le32, uint32_t);
LUALINUX_NEW_BYTESWAPPER(be16_to_cpu, uint32_t);
LUALINUX_NEW_BYTESWAPPER(be32_to_cpu, uint32_t);
LUALINUX_NEW_BYTESWAPPER(le16_to_cpu, uint32_t);
LUALINUX_NEW_BYTESWAPPER(le32_to_cpu, uint32_t);
#ifdef __LP64__
LUALINUX_NEW_BYTESWAPPER(cpu_to_be64, uint32_t);
LUALINUX_NEW_BYTESWAPPER(cpu_to_le64, uint32_t);
LUALINUX_NEW_BYTESWAPPER(be64_to_cpu, uint32_t);
LUALINUX_NEW_BYTESWAPPER(le64_to_cpu, uint32_t);
#endif

/***
* Table of task state constants.
* Exports task state flags from `<linux/sched.h>`. These are used with
* `linux.schedule()`.
*
* @table task
*   @tfield integer INTERRUPTIBLE Task is waiting for a signal or a resource (sleeping), can be interrupted.
*   @tfield integer UNINTERRUPTIBLE Task is waiting (sleeping), cannot be interrupted by signals (except fatal ones if KILLABLE is also implied by context).
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
*
* @table stat
*   @tfield integer IRWXU Read, write, execute for owner. (S_IRWXU)
*   @tfield integer IRUSR Read for owner. (S_IRUSR)
*   @tfield integer IWUSR Write for owner. (S_IWUSR)
*   @tfield integer IXUSR Execute for owner. (S_IXUSR)
*   @tfield integer IRWXG Read, write, execute for group. (S_IRWXG)
*   @tfield integer IRGRP Read for group. (S_IRGRP)
*   @tfield integer IWGRP Write for group. (S_IWGRP)
*   @tfield integer IXGRP Execute for group. (S_IXGRP)
*   @tfield integer IRWXO Read, write, execute for others. (S_IRWXO)
*   @tfield integer IROTH Read for others. (S_IROTH)
*   @tfield integer IWOTH Write for others. (S_IWOTH)
*   @tfield integer IXOTH Execute for others. (S_IXOTH)
*   @tfield integer IRWXUGO Read, write, execute for user, group, and others. (S_IRWXU|S_IRWXG|S_IRWXO)
*   @tfield integer IALLUGO All permissions for user, group, and others, including SUID, SGID, SVTX. (S_ISUID|S_ISGID|S_ISVTX|S_IRWXUGO)
*   @tfield integer IRUGO Read for user, group, and others. (S_IRUSR|S_IRGRP|S_IROTH)
*   @tfield integer IWUGO Write for user, group, and others. (S_IWUSR|S_IWGRP|S_IWOTH)
*   @tfield integer IXUGO Execute for user, group, and others. (S_IXUSR|S_IXGRP|S_IXOTH)
* @see device.new
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
* Table of error number constants.
* Exports common errno values from `<uapi/asm-generic/errno-base.h>`.
*
* @table errno
*   @tfield integer PERM Operation not permitted (EPERM).
*   @tfield integer NOENT No such file or directory (ENOENT).
*   @tfield integer SRCH No such process (ESRCH).
*   @tfield integer INTR Interrupted system call (EINTR).
*   @tfield integer IO I/O error (EIO).
*   @tfield integer NXIO No such device or address (ENXIO).
*   @tfield integer E2BIG Argument list too long (E2BIG). (Lua field name is "2BIG")
*   @tfield integer NOEXEC Exec format error (ENOEXEC).
*   @tfield integer BADF Bad file number (EBADF).
*   @tfield integer CHILD No child processes (ECHILD).
*   @tfield integer AGAIN Try again (EAGAIN).
*   @tfield integer NOMEM Out of memory (ENOMEM).
*   @tfield integer ACCES Permission denied (EACCES).
*   @tfield integer FAULT Bad address (EFAULT).
*   @tfield integer NOTBLK Block device required (ENOTBLK).
*   @tfield integer BUSY Device or resource busy (EBUSY).
*   @tfield integer EXIST File exists (EEXIST).
*   @tfield integer XDEV Cross-device link (EXDEV).
*   @tfield integer NODEV No such device (ENODEV).
*   @tfield integer NOTDIR Not a directory (ENOTDIR).
*   @tfield integer ISDIR Is a directory (EISDIR).
*   @tfield integer INVAL Invalid argument (EINVAL).
*   @tfield integer NFILE File table overflow (ENFILE).
*   @tfield integer MFILE Too many open files (EMFILE).
*   @tfield integer NOTTY Not a typewriter (ENOTTY).
*   @tfield integer TXTBSY Text file busy (ETXTBSY).
*   @tfield integer FBIG File too large (EFBIG).
*   @tfield integer NOSPC No space left on device (ENOSPC).
*   @tfield integer SPIPE Illegal seek (ESPIPE).
*   @tfield integer ROFS Read-only file system (EROFS).
*   @tfield integer MLINK Too many links (EMLINK).
*   @tfield integer PIPE Broken pipe (EPIPE).
*   @tfield integer DOM Math argument out of domain of func (EDOM).
*   @tfield integer RANGE Math result not representable (ERANGE).
*/
static const lunatik_reg_t lualinux_errno[] = {
	{"PERM", EPERM},	/* Operation not permitted */
	{"NOENT", ENOENT},	/* No such file or directory */
	{"SRCH", ESRCH},	/* No such process */
	{"INTR", EINTR},	/* Interrupted system call */
	{"IO", EIO},		/* I/O error */
	{"NXIO", ENXIO},	/* No such device or address */
	{"2BIG", E2BIG},	/* Argument list too long */
	{"NOEXEC", ENOEXEC},	/* Exec format error */
	{"BADF", EBADF},	/* Bad file number */
	{"CHILD", ECHILD},	/* No child processes */
	{"AGAIN", EAGAIN},	/* Try again */
	{"NOMEM", ENOMEM},	/* Out of memory */
	{"ACCES", EACCES},	/* Permission denied */
	{"FAULT", EFAULT},	/* Bad address */
	{"NOTBLK", ENOTBLK},	/* Block device required */
	{"BUSY", EBUSY},	/* Device or resource busy */
	{"EXIST", EEXIST},	/* File exists */
	{"XDEV", EXDEV},	/* Cross-device link */
	{"NODEV", ENODEV},	/* No such device */
	{"NOTDIR", ENOTDIR},	/* Not a directory */
	{"ISDIR", EISDIR},	/* Is a directory */
	{"INVAL", EINVAL},	/* Invalid argument */
	{"NFILE", ENFILE},	/* File table overflow */
	{"MFILE", EMFILE},	/* Too many open files */
	{"NOTTY", ENOTTY},	/* Not a typewriter */
	{"TXTBSY", ETXTBSY},	/* Text file busy */
	{"FBIG", EFBIG},	/* File too large */
	{"NOSPC", ENOSPC},	/* No space left on device */
	{"SPIPE", ESPIPE},	/* Illegal seek */
	{"ROFS", EROFS},	/* Read-only file system */
	{"MLINK", EMLINK},	/* Too many links */
	{"PIPE", EPIPE},	/* Broken pipe */
	{"DOM", EDOM},		/* Math argument out of domain of func */
	{"RANGE", ERANGE},	/* Math result not representable */
	{NULL, 0}
};

static const lunatik_namespace_t lualinux_flags[] = {
	{"stat", lualinux_stat},
	{"task", lualinux_task},
	{"errno", lualinux_errno},
	{NULL, NULL}
};

/***
* Byte Order Conversion
* @section byte_order
*/

/***
* Converts a 16-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh16
* @tparam integer num The 16-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 32-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh32
* @tparam integer num The 32-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 16-bit integer from host byte order to network (big-endian) byte order.
* @function hton16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/

/***
* Converts a 32-bit integer from host byte order to network (big-endian) byte order.
* @function hton32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/

/***
* Converts a 16-bit integer from host byte order to big-endian byte order.
* @function htobe16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/

/***
* Converts a 32-bit integer from host byte order to big-endian byte order.
* @function htobe32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/

/***
* Converts a 16-bit integer from host byte order to little-endian byte order.
* @function htole16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/

/***
* Converts a 32-bit integer from host byte order to little-endian byte order.
* @function htole32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/

/***
* Converts a 16-bit integer from big-endian byte order to host byte order.
* @function be16toh
* @tparam integer num The 16-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 32-bit integer from big-endian byte order to host byte order.
* @function be32toh
* @tparam integer num The 32-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 16-bit integer from little-endian byte order to host byte order.
* @function le16toh
* @tparam integer num The 16-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 32-bit integer from little-endian byte order to host byte order.
* @function le32toh
* @tparam integer num The 32-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 64-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh64
* @tparam integer num The 64-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 64-bit integer from host byte order to network (big-endian) byte order.
* @function hton64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/

/***
* Converts a 64-bit integer from host byte order to big-endian byte order.
* @function htobe64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/

/***
* Converts a 64-bit integer from host byte order to little-endian byte order.
* @function htole64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/

/***
* Converts a 64-bit integer from big-endian byte order to host byte order.
* @function be64toh
* @tparam integer num The 64-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/

/***
* Converts a 64-bit integer from little-endian byte order to host byte order.
* @function le64toh
* @tparam integer num The 64-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/
static const luaL_Reg lualinux_lib[] = {
	{"random", lualinux_random},
	{"schedule", lualinux_schedule},
	{"kill", lualinux_kill},
	{"tracing", lualinux_tracing},
	{"time", lualinux_time},
	{"difftime", lualinux_difftime},
	{"lookup", lualinux_lookup},
	{"ifindex", lualinux_ifindex},
	{"ntoh16", lualinux_be16_to_cpu},
	{"ntoh32", lualinux_be32_to_cpu},
	{"hton16", lualinux_cpu_to_be16},
	{"hton32", lualinux_cpu_to_be32},
	{"htobe16", lualinux_cpu_to_be16},
	{"htobe32", lualinux_cpu_to_be32},
	{"htole16", lualinux_cpu_to_le16},
	{"htole32", lualinux_cpu_to_le32},
	{"be16toh", lualinux_be16_to_cpu},
	{"be32toh", lualinux_be32_to_cpu},
	{"le16toh", lualinux_le16_to_cpu},
	{"le32toh", lualinux_le32_to_cpu},
#ifdef __LP64__
	{"ntoh64", lualinux_be64_to_cpu},
	{"hton64", lualinux_cpu_to_be64},
	{"htobe64", lualinux_cpu_to_be64},
	{"htole64", lualinux_cpu_to_le64},
	{"be64toh", lualinux_be64_to_cpu},
	{"le64toh", lualinux_le64_to_cpu},
#endif
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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");
