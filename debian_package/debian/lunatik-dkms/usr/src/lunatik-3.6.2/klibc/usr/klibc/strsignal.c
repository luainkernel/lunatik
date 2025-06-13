/*
 * strsignal.c
 */

#include <string.h>
#include <signal.h>
#include <stdio.h>

char *strsignal(int sig)
{
	static char buf[64];

	if ((unsigned)sig < _NSIG && sys_siglist[sig])
		return (char *)sys_siglist[sig];

#ifdef SIGRTMIN
	if (sig >= SIGRTMIN && sig <= SIGRTMAX) {
		snprintf(buf, sizeof buf, "Real-time signal %d",
			 sig - SIGRTMIN);
		return buf;
	}
#endif

	snprintf(buf, sizeof buf, "Signal %d", sig);
	return buf;
}
