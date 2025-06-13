/*
 * arch/ia64/include/klibc/archsignal.h
 *
 * Architecture-specific signal definitions.
 *
 */

#ifndef _KLIBC_ARCHSIGNAL_H
#define _KLIBC_ARCHSIGNAL_H

#include <asm/signal.h>
#define _NSIG        64
#define _NSIG_BPW    64
#define _NSIG_WORDS (_NSIG / _NSIG_BPW)

typedef struct {
	unsigned long sig[_NSIG_WORDS];
} sigset_t;

struct sigaction {
	union {
		__sighandler_t _sa_handler;
		void (*_sa_sigaction) (int, struct siginfo *, void *);
	} _u;
	unsigned long	sa_flags;
	sigset_t	sa_mask;
};

#define sa_handler      _u._sa_handler
#define sa_sigaction    _u._sa_sigaction

#endif
