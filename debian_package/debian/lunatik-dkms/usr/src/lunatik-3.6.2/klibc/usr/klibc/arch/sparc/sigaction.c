/*
 * sigaction.c
 */

#include <signal.h>
#include <sys/syscall.h>

__extern void __sigreturn(void);
__extern int ____rt_sigaction(int, const struct sigaction *, struct sigaction *,
			      void (*)(void), size_t);

int __rt_sigaction(int sig, const struct sigaction *act,
		   struct sigaction *oact, size_t size)
{
	void (*restorer)(void);

	restorer = (act && act->sa_flags & SA_RESTORER)
		? (void (*)(void))((uintptr_t)act->sa_restorer - 8)
		: NULL;
	return ____rt_sigaction(sig, act, oact, restorer, size);
}
