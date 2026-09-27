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
* Reads and changes the signal state of the calling task, and sends signals.
* `sigmask`, `sigpending` and `sigstate` act on the calling task, which is meaningful in a process
* runtime, typically in a kernel thread's body. In a softirq or hardirq callback the calling task is
* whichever one the interrupt found running, and `sigmask` must not be called there. `kill`
* resolves the pid in the calling task's pid namespace.
* @module signal
* @usage
*   local signal = require("signal")
*   local sig    = require("linux.signal")
*
*   signal.sigmask(sig.USR1)                 -- block SIGUSR1
*   print(signal.sigstate(sig.USR1))         -- true
*   signal.sigmask(sig.USR1, sig._UNBLOCK)
*/

/***
* Modifies signal mask for current task.
* Unlike the system call, it blocks `SIGKILL` and `SIGSTOP` too.
*
* @function sigmask
* @tparam integer sig Signal number, 1 to `_NSIG`.
* @tparam[opt] integer cmd SIG_BLOCK (0, default) or SIG_UNBLOCK (1).
* @raise Error if the signal or the command is out of bounds.
*/
static int luasignal_sigmask(lua_State *L)
{
	sigset_t newmask;
	sigemptyset(&newmask);

	int signum = lunatik_checkinteger(L, 1, 1, _NSIG);
	lua_Integer cmd = luaL_optinteger(L, 2, SIG_BLOCK);
	lunatik_checkbounds(L, 2, cmd, SIG_BLOCK, SIG_UNBLOCK);

	sigaddset(&newmask, signum);

	lunatik_try(L, sigprocmask, cmd, &newmask, NULL);
	return 0;
}

/***
* Checks if the current task has pending signals.
*
* @function sigpending
* @treturn boolean
*/
static int luasignal_sigpending(lua_State *L)
{
	lua_pushboolean(L, signal_pending(current));
	return 1;
}

/***
* Checks signal state for current task.
*
* @function sigstate
* @tparam integer sig Signal number, 1 to `_NSIG`.
* @tparam[opt] string state `"blocked"` (default), `"pending"`, or `"allowed"`. `"pending"` reads
*   the thread's private pending set: a signal sent to the process, as `kill` sends it, sits in the
*   shared set and reads as not pending, so `sigpending` is the check for it.
* @treturn boolean
* @raise Error if the signal is out of bounds.
* @usage
* local signal = require("signal")
* local sig    = require("linux.signal")
* signal.sigstate(sig.TERM) -- check if SIGTERM is blocked
* signal.sigstate(sig.TERM, "pending")
*/
static int luasignal_sigstate(lua_State *L)
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

	int signum = lunatik_checkinteger(L, 1, 1, _NSIG);
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
* Sends a signal to a process.
*
* @function kill
* @tparam integer pid Target process ID, 1 to `PID_MAX_LIMIT`.
* @tparam[opt] integer sig Signal to send, 0 to `_NSIG` (default: `KILL`, from `linux.signal`);
*   0 sends nothing and checks that the process exists.
* @treturn boolean `true` on success.
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

	lua_pushboolean(L, true);
	return 1;
}

static const luaL_Reg luasignal_lib[] = {
	{"sigmask", luasignal_sigmask},
	{"sigpending", luasignal_sigpending},
	{"sigstate", luasignal_sigstate},
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
MODULE_AUTHOR("L Venkata Subramanyam <202301280@dau.ac.in>");

