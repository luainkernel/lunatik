/*
* SPDX-FileCopyrightText: (c) 2025-2026 L Venkata Subramanyam <202301280@dau.ac.in>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/module.h>
#include <linux/sched/signal.h>
#include <linux/pid.h>
#include <linux/pid_namespace.h>
#include <linux/threads.h>
#include <linux/signal.h>

#include <lunatik.h>

/***
* Sends signals to processes.
* @module signal
* @usage
*   local signal = require("signal")
*   local sig    = require("linux.signal")
*
*   signal.kill(1234, sig.TERM)
*/

typedef struct luasignal_s {
	lunatik_defer_t defer;
	struct pid *pid;
	int sig;
} luasignal_t;

static DEFINE_PER_CPU(luasignal_t, luasignal_deferred);

/* a CPU holds a siglock only with IRQs off */
#define luasignal_isdeferred(sig)	((sig) != 0 && irqs_disabled())

static void luasignal_send(struct work_struct *work)
{
	luasignal_t *deferred = container_of(work, luasignal_t, defer.work);
	int sig = deferred->sig;
	struct pid *pid = xchg(&deferred->pid, NULL); /* sig is read first: the next call writes it */

	kill_pid(pid, sig, 1);
	put_pid(pid);
}

static int luasignal_defer(struct pid *pid, int sig)
{
	luasignal_t *deferred = this_cpu_ptr(&luasignal_deferred);

	if (pid_task(pid, PIDTYPE_PID) == NULL)
		return -ESRCH;
	if (READ_ONCE(deferred->pid) != NULL)
		return -EBUSY;

	deferred->sig = sig;
	WRITE_ONCE(deferred->pid, get_pid(pid));
	lunatik_defer(&deferred->defer);
	return 0;
}

/***
* Sends a signal to a process.
*
* With IRQs disabled, as in every callback of a hardirq runtime, a probe's handlers among them, the
* process is looked up at the call and the signal is sent after it, on a kernel worker: each CPU
* holds one such signal until the worker sends it. With IRQs on, the signal is sent in place.
*
* @function kill
* @tparam integer pid Target process ID, 1 to `PID_MAX_LIMIT`, in the initial pid namespace: the
*   number `task:pid()` returns, whichever task makes the call.
* @tparam[opt] integer sig Signal to send, 0 to `_NSIG` (default: `KILL`, from `linux.signal`);
*   0 sends nothing and checks that the process exists.
* @treturn boolean `true` once the signal is sent, or deferred, or the process found for signal 0;
*   `false` with IRQs disabled when the CPU still holds a signal it deferred; `nil` and `"ESRCH"` if
*   no process has that pid.
* @raise Error if the pid or the signal is out of bounds. The signal is sent with the kernel's
*   privilege, so no permission check applies.
*/
static int luasignal_kill(lua_State *L)
{
	pid_t nr = lunatik_checkinteger(L, 1, 1, PID_MAX_LIMIT);
	lua_Integer sig = luaL_optinteger(L, 2, SIGKILL);
	lunatik_checkbounds(L, 2, sig, 0, _NSIG);

	rcu_read_lock();
	struct pid *pid = find_pid_ns(nr, &init_pid_ns); /* a pid no task holds is NULL: -ESRCH */
	int ret = luasignal_isdeferred(sig) ? luasignal_defer(pid, sig) : kill_pid(pid, sig, 1);
	rcu_read_unlock();

	if (ret == -ESRCH)
		return lunatik_pushfail(L, ret);
	if (ret && ret != -EBUSY)
		lunatik_throw(L, ret);

	lua_pushboolean(L, ret == 0);
	return 1;
}

static const luaL_Reg luasignal_lib[] = {
	{"kill", luasignal_kill},
	{NULL, NULL}
};

LUNATIK_NEWLIB(signal, luasignal_lib, NULL);

static int __init luasignal_init(void)
{
	int cpu;

	for_each_possible_cpu(cpu)
		lunatik_initdefer(&per_cpu_ptr(&luasignal_deferred, cpu)->defer, luasignal_send);
	return 0;
}

static void __exit luasignal_exit(void)
{
	int cpu;

	for_each_possible_cpu(cpu)
		lunatik_syncdefer(&per_cpu_ptr(&luasignal_deferred, cpu)->defer);
}

module_init(luasignal_init);
module_exit(luasignal_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("L Venkata Subramanyam <202301280@dau.ac.in>");

