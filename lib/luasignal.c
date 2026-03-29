/*
* SPDX-FileCopyrightText: (c) 2025-2026 L Venkata Subramanyam <202301280@dau.ac.in>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/module.h>
#include <linux/sched/signal.h>
#include <linux/pid.h>
#include <linux/signal.h>
#include <linux/errno.h>

#include <lunatik.h>

/***
* POSIX Signals
* @module signal
*/

/***
* Modifies signal mask for current task.
*
* @function sigmask
* @tparam integer sig Signal number.
* @tparam[opt] integer cmd SIG_BLOCK (0, default) or SIG_UNBLOCK (1).
* @raise Error if the signal is invalid or the operation is not permitted.
*/
static int luasignal_sigmask(lua_State *L)
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
* @tparam integer sig Signal number.
* @tparam[opt] string state `"blocked"` (default), `"pending"`, or `"allowed"`.
* @treturn boolean
* @usage
* signal.sigstate(15) -- check if SIGTERM is blocked
* signal.sigstate(signal.flags.TERM, "pending")
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
* Sends a signal to a process.
*
* @function kill
* @tparam integer pid Target process ID.
* @tparam[opt] integer sig Signal to send (default: `signal.flags.KILL`).
* @treturn boolean `true` on success.
* @raise Error if the process is not found or the operation is not permitted.
*/
static int luasignal_kill(lua_State *L)
{
	pid_t nr = (pid_t)luaL_checkinteger(L, 1);
	int sig = luaL_optinteger(L, 2, SIGKILL);
	struct pid *pid = find_get_pid(nr);

	if (pid == NULL)
		lunatik_throw(L, ESRCH);

	int ret = kill_pid(pid, sig, 1);
	put_pid(pid);

	if (ret)
		lunatik_throw(L, -ret);

	lua_pushboolean(L, true);
	return 1;
}

/***
* Signal constants.
* @table flags
*/
static const lunatik_reg_t luasignal_flags[] = {
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

static const lunatik_namespace_t luasignal_namespaces[] = {
	{"flags", luasignal_flags},
	{NULL, NULL}
};

static const luaL_Reg luasignal_lib[] = {
	{"sigmask", luasignal_sigmask},
	{"sigpending", luasignal_sigpending},
	{"sigstate", luasignal_sigstate},
	{"kill", luasignal_kill},
	{NULL, NULL}
};

LUNATIK_NEWLIB(signal, luasignal_lib, NULL, luasignal_namespaces);

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
MODULE_SOFTDEP("pre: lunatik");
MODULE_AUTHOR("L Venkata Subramanyam <202301280@dau.ac.in>");

