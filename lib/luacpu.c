/*
* SPDX-FileCopyrightText: (c) 2025 Enderson Maia <endersonmaia@gmail.com
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux CPU Lua interface.
*
* This module provides access to Linux's CPU abstractions.
*
* @module cpu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/cpumask.h>
#include <linux/kernel_stat.h>

#include <lunatik.h>

#define LUACPU_NUM(name)					\
static int luacpu_num_##name(lua_State *L) {			\
	lua_pushinteger(L, (lua_Integer)num_##name##_cpus());	\
	return 1;						\
}

/***
* Returns the number of possible CPUs in the system.
*
* @function num_possible
* @treturn integer The number of possible CPUs in the system
*/
LUACPU_NUM(possible)

/***
* Returns the number of CPUs present in the system.
*
* @function num_present
* @treturn integer The number of CPUs present in the system
*/
LUACPU_NUM(present)

/***
* Returns the number of online CPUs in the system.
*
* @function num_online
* @treturn integer The number of online CPUs in the system
*/
LUACPU_NUM(online)

#define luacpu_setstat(L, idx, kcs, name, NAME)				\
do {									\
	lua_pushinteger(L, (lua_Integer)kcs.cpustat[CPUTIME_##NAME]);	\
	lua_setfield(L, idx - 1, #name);				\
} while (0)

/***
* Gets CPU statistics for a specific CPU.
* Fetches kernel CPU statistics including user, nice, system, idle, iowait,
* irq, softirq, steal, guest, guest_nice and forceidle times.
*
* @function stats
* @tparam integer cpu The CPU number (0-based) to query.
* @treturn table A table containing CPU time statistics with the following fields:
*   @tfield integer user Time spent in user mode
*   @tfield integer nice Time spent in user mode with low priority (nice)
*   @tfield integer system Time spent in system mode
*   @tfield integer idle Time spent in idle task
*   @tfield integer iowait Time waiting for I/O to complete
*   @tfield integer irq Time servicing hardware interrupts
*   @tfield integer softirq Time servicing software interrupts
*   @tfield integer steal Time stolen by other operating systems (virtualized environment)
*   @tfield integer guest Time spent running a virtual CPU for guest OS
*   @tfield integer guest_nice Time spent running a niced guest
*   @tfield integer forceidle Time spent in forced idle (if CONFIG_SCHED_CORE is enabled)
* @raise Error if CPU is offline
* @usage
*   local cpu0 = cpu.stats(0)
*   print("CPU 0 user time:", cpu0.user)
*   print("CPU 0 idle time:", cpu0.idle)
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
static int luacpu_foreach_##name(lua_State *L) {	\
	unsigned int cpu;				\
	luaL_checktype(L, 1, LUA_TFUNCTION);		\
	for_each_##name##_cpu(cpu) {			\
		lua_pushvalue(L, 1);			\
		lua_pushinteger(L, cpu);		\
		lua_call(L, 1, 0);			\
	}						\
	return 0;					\
};

/***
* Iterates over all possible CPUs and calls a function for each.
*
* @function foreach_possible
* @tparam function callback Function to call for each possible CPU
* @usage
*   cpu.foreach_possible(function(cpu_num)
*       print("CPU", cpu.stats(cpu_num))
*   end)
*/
LUACPU_FOREACH(possible)

/***
* Iterates over all present CPUs and calls a function for each.
*
* @function foreach_present
* @tparam function callback Function to call for each present CPU
* @usage
*   cpu.foreach_present(function(cpu_num)
*       print("CPU", cpu.stats(cpu_num))
*   end)
*/
LUACPU_FOREACH(present)

/***
* Iterates over all online CPUs and calls a function for each.
*
* @function foreach_online
* @tparam function callback Function to call for each online CPU
* @usage
*   cpu.foreach_online(function(cpu_num)
*       print("CPU", cpu.stats(cpu_num))
*   end)
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
MODULE_AUTHOR("Enderson Maia <endersonmaia@gmail.com");
MODULE_DESCRIPTION("Lunatik interface to Linux's CPU abstractions.");

