/*
 * sigprocmask.c
 */

#include <signal.h>
#include <sys/syscall.h>
#include <klibc/sysconfig.h>

__extern int __rt_sigprocmask(int, const sigset_t *, sigset_t *, size_t);

int sigprocmask(int how, const sigset_t * set, sigset_t * oset)
{
	return __rt_sigprocmask(how, set, oset, sizeof(sigset_t));
}
