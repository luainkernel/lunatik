/*
 * arch/alpha/include/klibc/archsignal.h
 *
 * Architecture-specific signal definitions
 *
 */

#ifndef _KLIBC_ARCHSIGNAL_H
#define _KLIBC_ARCHSIGNAL_H

/*
 * This is identical to <asm/signal.h>, *except* for _NSIG and struct
 * sigaction, where it has the old definition and we need the new (RT)
 * definition.
 */

struct siginfo;

#define NSIG	64

typedef unsigned long sigset_t;

#define SIGHUP		 1
#define SIGINT		 2
#define SIGQUIT		 3
#define SIGILL		 4
#define SIGTRAP		 5
#define SIGABRT		 6
#define SIGEMT		 7
#define SIGFPE		 8
#define SIGKILL		 9
#define SIGBUS		10
#define SIGSEGV		11
#define SIGSYS		12
#define SIGPIPE		13
#define SIGALRM		14
#define SIGTERM		15
#define SIGURG		16
#define SIGSTOP		17
#define SIGTSTP		18
#define SIGCONT		19
#define SIGCHLD		20
#define SIGTTIN		21
#define SIGTTOU		22
#define SIGIO		23
#define SIGXCPU		24
#define SIGXFSZ		25
#define SIGVTALRM	26
#define SIGPROF		27
#define SIGWINCH	28
#define SIGINFO		29
#define SIGUSR1		30
#define SIGUSR2		31

#define SIGPOLL		SIGIO
#define SIGPWR		SIGINFO
#define SIGIOT		SIGABRT

#define SA_ONSTACK	0x00000001
#define SA_RESTART	0x00000002
#define SA_NOCLDSTOP	0x00000004
#define SA_NODEFER	0x00000008
#define SA_RESETHAND	0x00000010
#define SA_NOCLDWAIT	0x00000020
#define SA_SIGINFO	0x00000040

#define SA_ONESHOT	SA_RESETHAND
#define SA_NOMASK	SA_NODEFER

#define MINSIGSTKSZ	4096
#define SIGSTKSZ	16384

#define SIG_BLOCK	1
#define SIG_UNBLOCK	2
#define SIG_SETMASK	3

#include <asm-generic/signal-defs.h>

struct sigaction {
	union {
		__sighandler_t	sa_handler;
		void		(*sa_sigaction)(int, struct siginfo *, void *);
	};
        unsigned long   sa_flags;
        sigset_t        sa_mask;
};

#endif
