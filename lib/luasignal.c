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

/***
* Sends a signal to a process.
*
* @function kill
* @tparam integer pid Target process ID, 1 to `PID_MAX_LIMIT`, in the initial pid namespace: the
*   number `task:pid()` returns, whichever task makes the call.
* @tparam[opt] integer sig Signal to send, 0 to `_NSIG` (default: `KILL`, from `linux.signal`);
*   0 sends nothing and checks that the process exists.
* @treturn boolean `true` once the signal is sent, or the process found for signal 0; `nil` and
*   `"ESRCH"` if no process has that pid.
* @raise Error if the pid or the signal is out of bounds, and "not allowed with IRQs disabled"
*   when called with IRQs disabled, as in every callback of a hardirq runtime, a probe's handlers
*   among them, where the CPU may already hold a lock the signal takes. The signal is sent with the
*   kernel's privilege, so no permission check applies.
*/
static int luasignal_kill(lua_State *L)
{
	if (irqs_disabled())
		luaL_error(L, "not allowed with IRQs disabled");

	pid_t nr = lunatik_checkinteger(L, 1, 1, PID_MAX_LIMIT);
	lua_Integer sig = luaL_optinteger(L, 2, SIGKILL);
	lunatik_checkbounds(L, 2, sig, 0, _NSIG);

	rcu_read_lock();
	int ret = kill_pid(find_pid_ns(nr, &init_pid_ns), sig, 1); /* a pid no task holds is NULL: -ESRCH */
	rcu_read_unlock();

	if (ret == -ESRCH)
		return lunatik_pushfail(L, ret);
	if (ret)
		lunatik_throw(L, ret);

	lua_pushboolean(L, true);
	return 1;
}

static const luaL_Reg luasignal_lib[] = {
	{"kill", luasignal_kill},
	{NULL, NULL}
};

LUNATIK_NEWLIB(signal, luasignal_lib, NULL);

static int __init luasignal_init(void)
{
	return 0;
}

static void __exit luasignal_exit(void)
{
}

module_init(luasignal_init);
module_exit(luasignal_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("L Venkata Subramanyam <202301280@dau.ac.in>");

