/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/module.h>
#include <linux/random.h>
#include <linux/stat.h>
#include <linux/sched.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/byteorder/generic.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

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

static int lualinux_time(lua_State *L)
{
	lua_pushinteger(L, (lua_Integer)ktime_get_real_ns());
	return 1;
}

static int lualinux_difftime(lua_State *L)
{
	u64 t2 = (u64) luaL_checkinteger(L, 1);
	u64 t1 = (u64) luaL_checkinteger(L, 2);
	lua_pushinteger(L, (lua_Integer)(t2 - t1));
	return 1;
}

static int lualinux_lookup(lua_State *L)
{
	const char *symbol = luaL_checkstring(L, 1);

	lua_pushlightuserdata(L, lunatik_lookup(symbol));
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

static const lunatik_reg_t lualinux_task[] = {
	{"INTERRUPTIBLE", TASK_INTERRUPTIBLE},
	{"UNINTERRUPTIBLE", TASK_UNINTERRUPTIBLE},
	{"KILLABLE", TASK_KILLABLE},
	{"IDLE", TASK_IDLE},
	{NULL, 0}
};

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

static const luaL_Reg lualinux_lib[] = {
	{"random", lualinux_random},
	{"schedule", lualinux_schedule},
	{"tracing", lualinux_tracing},
	{"time", lualinux_time},
	{"difftime", lualinux_difftime},
	{"lookup", lualinux_lookup},
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

