/*
 * sigaction.c
 */

#include <signal.h>
#include <stddef.h>
#include <sys/syscall.h>
#include <klibc/sysconfig.h>

__extern void __sigreturn(void);

#if _KLIBC_NEEDS_SIGACTION_FIXUP
typedef struct sigaction *act_type;
#else
typedef const struct sigaction *act_type;
#endif

__extern int __rt_sigaction(int, act_type, struct sigaction *, size_t);

int sigaction(int sig, const struct sigaction *act, struct sigaction *oact)
{
	unsigned int needed_flags = 0
#if _KLIBC_NEEDS_SA_RESTORER
		| SA_RESTORER
#endif
#if _KLIBC_NEEDS_SA_SIGINFO
		| SA_SIGINFO
#endif
		;
	struct sigaction sa;
	int rv;

	if (act &&
	    ((act->sa_flags & needed_flags) != needed_flags ||
	     _KLIBC_NEEDS_SIGACTION_FIXUP)) {
		sa = *act;
		sa.sa_flags |= needed_flags;
#if _KLIBC_NEEDS_SA_RESTORER
		if (!(act->sa_flags & SA_RESTORER))
			sa.sa_restorer = &__sigreturn;
#endif
		act = &sa;
	}

	/* Check that we have the right signal API definitions */
	(void)sizeof(char[_NSIG >= 64 ? 1 : -1]);
	(void)sizeof(char[sizeof(sigset_t) * 8 >= _NSIG ? 1 : -1]);
	(void)sizeof(char[offsetof(struct sigaction, sa_mask)
			  + sizeof(sigset_t) == sizeof(struct sigaction)
			  ? 1 : -1]);

	rv = __rt_sigaction(sig, (act_type)act, oact, sizeof(sigset_t));

#if _KLIBC_NEEDS_SA_RESTORER
	if (oact && (oact->sa_restorer == &__sigreturn)) {
		oact->sa_flags &= ~SA_RESTORER;
	}
#endif

	return rv;
}
