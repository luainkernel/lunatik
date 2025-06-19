/*
 * sigaction.c
 */

#include <signal.h>
#include <sys/syscall.h>

__extern void __sigreturn(void);
__extern int ____rt_sigaction(int, const struct sigaction *, struct sigaction *,
			      size_t, void (*)(void));

int __rt_sigaction(int sig, const struct sigaction *act,
		   struct sigaction *oact, size_t size)
{
	return ____rt_sigaction(sig, act, oact, size, &__sigreturn);
}
