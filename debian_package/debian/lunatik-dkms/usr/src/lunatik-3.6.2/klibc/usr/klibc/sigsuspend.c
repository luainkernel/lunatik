/*
 * sigsuspend.c
 */

#include <signal.h>
#include <sys/syscall.h>
#include <klibc/sysconfig.h>
#include <klibc/havesyscall.h>

__extern int __rt_sigsuspend(const sigset_t *, size_t);

int sigsuspend(const sigset_t * mask)
{
	return __rt_sigsuspend(mask, sizeof *mask);
}
