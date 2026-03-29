/*
* SPDX-FileCopyrightText: (c) 2025 Enderson Maia <endersonmaia@gmail.com
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to Linux CPU abstractions.
* @module cpu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/cpumask.h>
#include <linux/kernel_stat.h>

#include <lunatik.h>

#define LUACPU_NUM(name)					\
static int luacpu_num_##name(lua_State *L)			\
{								\
	lua_pushinteger(L, (lua_Integer)num_##name##_cpus());	\
	return 1;						\
}

/***
* @function num_possible
* @treturn integer number of possible CPUs
*/
LUACPU_NUM(possible)

/***
* @function num_present
* @treturn integer number of present CPUs
*/
LUACPU_NUM(present)

/***
* @function num_online
* @treturn integer number of online CPUs
*/
LUACPU_NUM(online)

#define luacpu_setstat(L, idx, kcs, name, NAME)				\
do {									\
	lua_pushinteger(L, (lua_Integer)kcs.cpustat[CPUTIME_##NAME]);	\
	lua_setfield(L, idx - 1, #name);				\
} while (0)

/***
* Returns CPU time statistics for a given CPU.
* @function stats
* @tparam integer cpu CPU number (0-based)
* @treturn table fields: `user`, `nice`, `system`, `idle`, `iowait`, `irq`,
*   `softirq`, `steal`, `guest`, `guest_nice`, `forceidle` (if CONFIG_SCHED_CORE)
* @raise if CPU is offline
*/
static int luacpu_stats(lua_State *L)
{
	unsigned int cpu = luaL_checkinteger(L, 1);
	struct kernel_cpustat kcs;

	luaL_argcheck(L, cpu_online(cpu), 1, "CPU is offline");

	kcpustat_cpu_fetch(&kcs, cpu);

	lua_createtable(L, 0, NR_STATS);

	luacpu_setstat(L, -1, kcs, user, USER);
	luacpu_setstat(L, -1, kcs, nice, NICE);
	luacpu_setstat(L, -1, kcs, system, SYSTEM);
	luacpu_setstat(L, -1, kcs, idle, IDLE);
	luacpu_setstat(L, -1, kcs, iowait, IOWAIT);
	luacpu_setstat(L, -1, kcs, irq, IRQ);
	luacpu_setstat(L, -1, kcs, softirq, SOFTIRQ);
	luacpu_setstat(L, -1, kcs, steal, STEAL);
	luacpu_setstat(L, -1, kcs, guest, GUEST);
	luacpu_setstat(L, -1, kcs, guest_nice, GUEST_NICE);
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0)) && defined(CONFIG_SCHED_CORE)
	luacpu_setstat(L, -1, kcs, forceidle, FORCEIDLE);
#endif
	return 1;
}

#define LUACPU_FOREACH(name)				\
static int luacpu_foreach_##name(lua_State *L)		\
{							\
	unsigned int cpu;				\
	luaL_checktype(L, 1, LUA_TFUNCTION);		\
	for_each_##name##_cpu(cpu) {			\
		lua_pushvalue(L, 1);			\
		lua_pushinteger(L, cpu);		\
		lua_call(L, 1, 0);			\
	}						\
	return 0;					\
}

/***
* Calls a function for each possible CPU.
* @function foreach_possible
* @tparam function callback called with the CPU number
*/
LUACPU_FOREACH(possible)

/***
* Calls a function for each present CPU.
* @function foreach_present
* @tparam function callback called with the CPU number
*/
LUACPU_FOREACH(present)

/***
* Calls a function for each online CPU.
* @function foreach_online
* @tparam function callback called with the CPU number
*/
LUACPU_FOREACH(online)

static const luaL_Reg luacpu_lib[] = {
	{"num_possible", luacpu_num_possible},
	{"num_present", luacpu_num_present},
	{"num_online", luacpu_num_online},
	{"stats", luacpu_stats},
	{"foreach_possible", luacpu_foreach_possible},
	{"foreach_present", luacpu_foreach_present},
	{"foreach_online", luacpu_foreach_online},
	{NULL, NULL}
};

LUNATIK_NEWLIB(cpu, luacpu_lib, NULL, NULL);

static int __init luacpu_init(void)
{
	return 0;
}

static void __exit luacpu_exit(void)
{
}

module_init(luacpu_init);
module_exit(luacpu_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_SOFTDEP("pre: lunatik");
MODULE_AUTHOR("Enderson Maia <endersonmaia@gmail.com>");
MODULE_DESCRIPTION("Lunatik interface to Linux's CPU abstractions.");

