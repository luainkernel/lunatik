/*
 * sigabbrev.h
 *
 * Construct the abbreviated signal list
 */

#include <signal.h>
#include <unistd.h>

const char *const sys_sigabbrev[NSIG] = {
#ifdef SIGABRT
	[SIGABRT] = "ABRT",
#endif
#ifdef SIGALRM
	[SIGALRM] = "ALRM",
#endif
#ifdef SIGBUS
	[SIGBUS] = "BUS",
#endif
#ifdef SIGCHLD
	[SIGCHLD] = "CHLD",
#endif
#if defined(SIGCLD) && (SIGCHLD != SIGCLD)
	[SIGCLD] = "CLD",
#endif
#ifdef SIGEMT
	[SIGEMT] = "EMT",
#endif
#ifdef SIGFPE
	[SIGFPE] = "FPE",
#endif
#ifdef SIGHUP
	[SIGHUP] = "HUP",
#endif
#ifdef SIGILL
	[SIGILL] = "ILL",
#endif
	/* SIGINFO == SIGPWR */
#ifdef SIGINT
	[SIGINT] = "INT",
#endif
#ifdef SIGIO
	[SIGIO] = "IO",
#endif
#if defined(SIGIOT) && (SIGIOT != SIGABRT)
	[SIGIOT] = "IOT",
#endif
#ifdef SIGKILL
	[SIGKILL] = "KILL",
#endif
#if defined(SIGLOST) && (SIGLOST != SIGIO) && (SIGLOST != SIGPWR)
	[SIGLOST] = "LOST",
#endif
#ifdef SIGPIPE
	[SIGPIPE] = "PIPE",
#endif
#if defined(SIGPOLL) && (SIGPOLL != SIGIO)
	[SIGPOLL] = "POLL",
#endif
#ifdef SIGPROF
	[SIGPROF] = "PROF",
#endif
#ifdef SIGPWR
	[SIGPWR] = "PWR",
#endif
#ifdef SIGQUIT
	[SIGQUIT] = "QUIT",
#endif
	/* SIGRESERVE == SIGUNUSED */
#ifdef SIGSEGV
	[SIGSEGV] = "SEGV",
#endif
#ifdef SIGSTKFLT
	[SIGSTKFLT] = "STKFLT",
#endif
#ifdef SIGSTOP
	[SIGSTOP] = "STOP",
#endif
#ifdef SIGSYS
	[SIGSYS] = "SYS",
#endif
#ifdef SIGTERM
	[SIGTERM] = "TERM",
#endif
#ifdef SIGTSTP
	[SIGTSTP] = "TSTP",
#endif
#ifdef SIGTTIN
	[SIGTTIN] = "TTIN",
#endif
#ifdef SIGTTOU
	[SIGTTOU] = "TTOU",
#endif
#ifdef SIGURG
	[SIGURG] = "URG",
#endif
#ifdef SIGUSR1
	[SIGUSR1] = "USR1",
#endif
#ifdef SIGUSR2
	[SIGUSR2] = "USR2",
#endif
#ifdef SIGVTALRM
	[SIGVTALRM] = "VTALRM",
#endif
#ifdef SIGWINCH
	[SIGWINCH] = "WINCH",
#endif
#ifdef SIGXCPU
	[SIGXCPU] = "XCPU",
#endif
#ifdef SIGXFSZ
	[SIGXFSZ] = "XFSZ",
#endif
#ifdef SIGTRAP
	[SIGTRAP] = "TRAP",
#endif
#ifdef SIGCONT
	[SIGCONT] = "CONT",
#endif
};
