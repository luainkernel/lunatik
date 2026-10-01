/*
* SPDX-FileCopyrightText: (c) 2025-2026 L Venkata Subramanyam <202301280@dau.ac.in>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/module.h>
#include <linux/sched/signal.h>
#include <linux/pid.h>
#include <linux/threads.h>
#include <linux/signal.h>
#include <linux/errno.h>

#include <lunatik.h>

/***
* Sends signals to processes.
* `kill` resolves the pid in the calling task's pid namespace.
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
* @tparam integer pid Target process ID, 1 to `PID_MAX_LIMIT`.
* @tparam[opt] integer sig Signal to send, 0 to `_NSIG` (default: `KILL`, from `linux.signal`);
*   0 sends nothing and checks that the process exists.
* @raise Error if the pid or the signal is out of bounds; "ESRCH" if no process has that pid. The
*   signal is sent with the kernel's privilege, so no permission check applies.
*/
static int luasignal_kill(lua_State *L)
{
	pid_t nr = lunatik_checkinteger(L, 1, 1, PID_MAX_LIMIT);
	lua_Integer sig = luaL_optinteger(L, 2, SIGKILL);
	lunatik_checkbounds(L, 2, sig, 0, _NSIG);
	struct pid *pid = find_get_pid(nr);

	if (pid == NULL)
		lunatik_throw(L, -ESRCH);

	int ret = kill_pid(pid, sig, 1);
	put_pid(pid);

	if (ret)
		lunatik_throw(L, -ret);

	return 0;
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

