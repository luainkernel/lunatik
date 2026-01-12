/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
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
#include <linux/signal.h>
#include <linux/errno.h>

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
* Modifies signal mask for current task.
*
* @function sigmask
* @tparam integer sig Signal number
* @tparam[opt] integer cmd 0=BLOCK (default), 1=UNBLOCK
* @raise error string on failure (EINVAL, EPERM, etc.)
* @within linux
* @usage
*   pcall(linux.sigmask, 15) -- Block SIGTERM
*   pcall(linux.sigmask, 15, 1) -- Unblock SIGTERM
*/
static int lualinux_sigmask(lua_State *L)
{
    sigset_t newmask;
    sigemptyset(&newmask);
    
    int signum = luaL_checkinteger(L, 1);
    int cmd = luaL_optinteger(L, 2, 0);
    
    sigaddset(&newmask, signum);

    lunatik_try(L, sigprocmask, cmd, &newmask, NULL);
    return 0;
}

/***
* Checks current task pending signals.
*
* @function sigpending
* @treturn boolean
* @within linux
* @usage
*   linux.sigpending()
*/
static int lualinux_sigpending(lua_State *L)
{
 	lua_pushboolean(L, signal_pending(current));
    return 1;
}

/***
* Checks signal state for current task.
*
* @function sigstate
* @tparam integer sig Signal number
* @tparam[opt] string state One of: "blocked", "pending", "allowed"
* @treturn boolean
* @within linux
* @usage
*   linux.sigstate(15) -- check if SIGTERM is blocked (default)
*   linux.sigstate(linux.signal.TERM, "pending")
*/
static int lualinux_sigstate(lua_State *L)
{
    enum sigstate_cmd {
        SIGSTATE_BLOCKED,
        SIGSTATE_PENDING,
        SIGSTATE_ALLOWED,
    };

    const char *const sigstate_opts[] = {
        [SIGSTATE_BLOCKED] = "blocked",
        [SIGSTATE_PENDING] = "pending",
        [SIGSTATE_ALLOWED] = "allowed",
    };

    int signum = luaL_checkinteger(L, 1);
    enum sigstate_cmd cmd = (enum sigstate_cmd)luaL_checkoption(L, 2, "blocked", sigstate_opts);

    bool result;
    switch (cmd) {
    case SIGSTATE_BLOCKED:
        result = sigismember(&current->blocked, signum);
        break;
    case SIGSTATE_PENDING:
        result = sigismember(&current->pending.signal, signum);
        break;
    case SIGSTATE_ALLOWED:
        result = !sigismember(&current->blocked, signum);
        break;
    }

    lua_pushboolean(L, result);
    return 1;
}

/***
* Kills a process by sending a signal.
* By default, sends SIGKILL.
* An optional second argument can specify a different signal
* (either by number or by using the constants from `linux.signal`).
*
* @function kill
* @tparam integer pid Process ID to kill.
* @tparam[opt] integer sig Signal number to send (default: `linux.signal.KILL`).
* @treturn boolean `true` if the signal was sent successfully.
* @treturn[error] boolean `false` followed by an error number if the operation fails.
* @raise Errors:
*   - (3): The specified PID doesn't exist
*   - other errno values depending on the failure cause (e.g., `EPERM`, `EINVAL`, etc.)
* @usage
*   linux.kill(1234)  -- Kill process 1234 with SIGKILL (default)
*   linux.kill(1234, linux.signal.TERM)  -- Kill process 1234 with SIGTERM
*/
static int lualinux_kill(lua_State *L)
{
	pid_t nr = (pid_t)luaL_checkinteger(L, 1);
  	int sig = luaL_optinteger(L, 2, SIGKILL);
 	struct pid *pid = find_get_pid(nr);

	int ret = ESRCH;
	if (pid == NULL) 
        	goto err;    
	
    	ret = kill_pid(pid, sig, 1);
    	put_pid(pid);
    
    	if (ret) 
		goto err;
    
    	lua_pushboolean(L, true);
    	return 1;
err:
	lua_pushboolean(L, false);
	lua_pushinteger(L, ret);
	return 2;
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
* Byte Order Conversion
* @section byte_order
*/
#define LUALINUX_BYTESWAPPER(swapper, T)		\
static int lualinux_##swapper(lua_State *L)		\
{							\
	T x = (T)luaL_checkinteger(L, 1);		\
	lua_pushinteger(L, (lua_Integer)swapper(x));	\
	return 1;					\
}

/***
* Converts a 16-bit integer from host byte order to big-endian byte order.
* @function htobe16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/
LUALINUX_BYTESWAPPER(cpu_to_be16, u16);

/***
* Converts a 32-bit integer from host byte order to big-endian byte order.
* @function htobe32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/
LUALINUX_BYTESWAPPER(cpu_to_be32, u32);

/***
* Converts a 16-bit integer from host byte order to little-endian byte order.
* @function htole16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/
LUALINUX_BYTESWAPPER(cpu_to_le16, u16);

/***
* Converts a 32-bit integer from host byte order to little-endian byte order.
* @function htole32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/
LUALINUX_BYTESWAPPER(cpu_to_le32, u32);

/***
* Converts a 16-bit integer from big-endian byte order to host byte order.
* @function be16toh
* @tparam integer num The 16-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUALINUX_BYTESWAPPER(be16_to_cpu, u16);

/***
* Converts a 32-bit integer from big-endian byte order to host byte order.
* @function be32toh
* @tparam integer num The 32-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUALINUX_BYTESWAPPER(be32_to_cpu, u32);

/***
* Converts a 16-bit integer from little-endian byte order to host byte order.
* @function le16toh
* @tparam integer num The 16-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUALINUX_BYTESWAPPER(le16_to_cpu, u16);

/***
* Converts a 32-bit integer from little-endian byte order to host byte order.
* @function le32toh
* @tparam integer num The 32-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUALINUX_BYTESWAPPER(le32_to_cpu, u32);

/***
* Converts a 64-bit integer from host byte order to big-endian byte order.
* @function htobe64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/
LUALINUX_BYTESWAPPER(cpu_to_be64, u64);

/***
* Converts a 64-bit integer from host byte order to little-endian byte order.
* @function htole64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/
LUALINUX_BYTESWAPPER(cpu_to_le64, u64);

/***
* Converts a 64-bit integer from big-endian byte order to host byte order.
* @function be64toh
* @tparam integer num The 64-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUALINUX_BYTESWAPPER(be64_to_cpu, u64);

/***
* Converts a 64-bit integer from little-endian byte order to host byte order.
* @function le64toh
* @tparam integer num The 64-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUALINUX_BYTESWAPPER(le64_to_cpu, u64);

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
* Table of signal constants for use with `linux.kill`.
* This table provides named constants for the standard Linux signals.
* For example, `linux.signal.TERM` corresponds to SIGTERM (15).
*/
static const lunatik_reg_t lualinux_signal[] = {
    	{"HUP", SIGHUP},
	{"INT", SIGINT},
	{"QUIT", SIGQUIT},
	{"ILL", SIGILL},
	{"TRAP", SIGTRAP},
	{"ABRT", SIGABRT},
	{"BUS", SIGBUS},
	{"FPE", SIGFPE},
	{"KILL", SIGKILL},
	{"USR1", SIGUSR1},
	{"SEGV", SIGSEGV},
	{"USR2", SIGUSR2},
	{"PIPE", SIGPIPE},
	{"ALRM", SIGALRM},
	{"TERM", SIGTERM},
#ifdef SIGSTKFLT
	{"STKFLT", SIGSTKFLT},
#endif
	{"CHLD", SIGCHLD},
	{"CONT", SIGCONT},
	{"STOP", SIGSTOP},
	{"TSTP", SIGTSTP},
	{"TTIN", SIGTTIN},
	{"TTOU", SIGTTOU},
	{"URG", SIGURG},
	{"XCPU", SIGXCPU},
	{"XFSZ", SIGXFSZ},
	{"VTALRM", SIGVTALRM},
	{"PROF", SIGPROF},
	{"WINCH", SIGWINCH},
	{"IO", SIGIO},
	{"PWR", SIGPWR},
	{"SYS", SIGSYS},
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
	{"signal", lualinux_signal},
	{NULL, NULL}
};

static const luaL_Reg lualinux_lib[] = {
	{"random", lualinux_random},
	{"schedule", lualinux_schedule},
	{"sigmask", lualinux_sigmask},
	{"sigpending", lualinux_sigpending},
	{"sigstate", lualinux_sigstate},
	{"kill", lualinux_kill},
	{"tracing", lualinux_tracing},
	{"time", lualinux_time},
	{"difftime", lualinux_difftime},
	{"lookup", lualinux_lookup},
	{"ifindex", lualinux_ifindex},
	{"errname", lualinux_errname},
/***
* Converts a 16-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh16
* @tparam integer num The 16-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/
	{"ntoh16", lualinux_be16_to_cpu},
/***
* Converts a 32-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh32
* @tparam integer num The 32-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/
	{"ntoh32", lualinux_be32_to_cpu},
/***
* Converts a 16-bit integer from host byte order to network (big-endian) byte order.
* @function hton16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/
	{"hton16", lualinux_cpu_to_be16},
/***
* Converts a 32-bit integer from host byte order to network (big-endian) byte order.
* @function hton32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/
	{"hton32", lualinux_cpu_to_be32},
	{"htobe16", lualinux_cpu_to_be16},
	{"htobe32", lualinux_cpu_to_be32},
	{"htole16", lualinux_cpu_to_le16},
	{"htole32", lualinux_cpu_to_le32},
	{"be16toh", lualinux_be16_to_cpu},
	{"be32toh", lualinux_be32_to_cpu},
	{"le16toh", lualinux_le16_to_cpu},
	{"le32toh", lualinux_le32_to_cpu},
/***
* Converts a 64-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh64
* @tparam integer num The 64-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/
	{"ntoh64", lualinux_be64_to_cpu},
/***
* Converts a 64-bit integer from host byte order to network (big-endian) byte order.
* @function hton64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/
	{"hton64", lualinux_cpu_to_be64},
	{"htobe64", lualinux_cpu_to_be64},
	{"htole64", lualinux_cpu_to_le64},
	{"be64toh", lualinux_be64_to_cpu},
	{"le64toh", lualinux_le64_to_cpu},
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

