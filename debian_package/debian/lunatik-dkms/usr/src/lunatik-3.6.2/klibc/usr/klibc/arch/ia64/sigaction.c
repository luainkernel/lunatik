/*
 * sigaction.c
 */

#include <signal.h>
#include <sys/syscall.h>

/* We use -mno-pic so our function pointers are straight to the function entry
   point, but the kernel always expects a descriptor. Thus we create a fake
   descriptor for each possible signal, update it, and pass that to the kernel
   instead (the descriptor must remain valid after returning from sigaction
   until it is replaced). */
static struct {
	uintptr_t entry;
	uintptr_t gp;
} signal_descriptors[_NSIG];

__extern int ____rt_sigaction(int, const struct sigaction *, struct sigaction *,
			      size_t);

int __rt_sigaction(int sig, struct sigaction *act,
		   struct sigaction *oact, size_t size)
{
	sigset_t signal_mask, old_signal_mask;
	uintptr_t old_entry;
	int rv;

	if (sig < 0 || sig >= _NSIG) {
		errno = EINVAL;
		return -1;
	}

	/* Mask the signal to avoid races on access to its descriptor */
	sigemptyset(&signal_mask);
	sigaddset(&signal_mask, sig);
	rv = sigprocmask(SIG_BLOCK, &signal_mask, &old_signal_mask);
	if (rv)
		return -1;

	if (oact) {
		old_entry = signal_descriptors[sig].entry;
	}

	if (act && act->sa_handler != SIG_IGN && act->sa_handler != SIG_DFL) {
		signal_descriptors[sig].entry = (uintptr_t)act->sa_handler;
		act->sa_handler =
			(__sighandler_t)(uintptr_t)&signal_descriptors[sig];
	}

	rv = ____rt_sigaction(sig, act, oact, size);

	if (rv)
		signal_descriptors[sig].entry = old_entry;

	/* Restore signal mask */
	(void)sigprocmask(SIG_SETMASK, &old_signal_mask, NULL);

	if (oact && oact->sa_handler != SIG_IGN &&
	    oact->sa_handler != SIG_DFL) {
		oact->sa_handler = (__sighandler_t)old_entry;
	}

	return rv;
}
