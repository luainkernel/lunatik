/*
* SPDX-FileCopyrightText: (c) 2025-2026 Enderson Maia <endersonmaia@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to Linux CPU abstractions.
* A possible CPU is one the system can ever bring up, a present one is plugged in, and an online
* one runs tasks. `linux.numcpus()` is one past the highest possible CPU id, the same count as
* `num_possible` when those ids have no gaps.
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
* Returns the number of possible CPUs.
* @function num_possible
* @treturn integer number of possible CPUs
*/
LUACPU_NUM(possible)

/***
* Returns the number of present CPUs.
* @function num_present
* @treturn integer number of present CPUs
*/
LUACPU_NUM(present)

/***
* Returns the number of online CPUs.
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
* Returns the time a CPU spent in each state since boot, in nanoseconds.
* `idle` and `iowait` are what the tick accounts, which lags `/proc/stat` on a
* tickless CPU while it idles.
* @function stats
* @tparam integer cpu CPU number, from `0` to `linux.numcpus() - 1`
* @treturn table fields: `user`, `nice`, `system`, `idle`, `iowait`, `irq`,
*   `softirq`, `steal`, `guest`, `guest_nice`, `forceidle` (if CONFIG_SCHED_CORE)
* @raise "out of bounds" if cpu is outside that range, "CPU is offline" if it is not online
*/
static int luacpu_stats(lua_State *L)
{
	unsigned int cpu = (unsigned int)lunatik_checkinteger(L, 1, 0, nr_cpu_ids - 1);
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
#ifdef CONFIG_SCHED_CORE
	luacpu_setstat(L, -1, kcs, forceidle, FORCEIDLE);
#endif
	return 1;
}

#define LUACPU_ITERATOR(name)								\
static int luacpu_next##name(lua_State *L)						\
{											\
	int cpu = (int)lunatik_checkinteger(L, 2, LUNATIK_CPU_NONE, nr_cpu_ids - 1);	\
	unsigned int next = cpumask_next(cpu, cpu_##name##_mask);			\
	lunatik_pushoptinteger(L, next < nr_cpu_ids, next);				\
	return 1;									\
}											\
											\
static int luacpu_##name(lua_State *L)							\
{											\
	lua_pushcfunction(L, luacpu_next##name);					\
	lua_pushnil(L);									\
	lua_pushinteger(L, LUNATIK_CPU_NONE);						\
	return 3;									\
}

/***
* Iterates over the possible CPUs, in ascending order.
* @function possible
* @treturn function iterator for the generic `for`, yielding each possible CPU id
* @usage
*   for id in cpu.possible() do print(id) end
*/
LUACPU_ITERATOR(possible)

/***
* Iterates over the present CPUs, in ascending order.
* @function present
* @treturn function iterator for the generic `for`, yielding each present CPU id
* @usage
*   for id in cpu.present() do print(id) end
*/
LUACPU_ITERATOR(present)

/***
* Iterates over the online CPUs, in ascending order.
* @function online
* @treturn function iterator for the generic `for`, yielding each online CPU id
* @usage
*   for id in cpu.online() do print(id) end
*/
LUACPU_ITERATOR(online)

static const luaL_Reg luacpu_lib[] = {
	{"num_possible", luacpu_num_possible},
	{"num_present", luacpu_num_present},
	{"num_online", luacpu_num_online},
	{"stats", luacpu_stats},
	{"possible", luacpu_possible},
	{"present", luacpu_present},
	{"online", luacpu_online},
	{NULL, NULL}
};

LUNATIK_NEWLIB(cpu, luacpu_lib, NULL);

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
MODULE_AUTHOR("Enderson Maia <endersonmaia@gmail.com>");
MODULE_DESCRIPTION("Lunatik interface to Linux's CPU abstractions.");

