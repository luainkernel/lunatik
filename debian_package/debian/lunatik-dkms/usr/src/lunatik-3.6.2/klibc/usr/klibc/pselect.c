/*
 * pselect.c
 */

#include <sys/select.h>
#include <sys/syscall.h>

struct __pselect6 {
	const sigset_t *sigmask;
	size_t sigsize;
};

__extern int __pselect6(int, fd_set *, fd_set *, fd_set *,
			const struct timespec *, const struct __pselect6 *);

int pselect(int n, fd_set * readfds, fd_set * writefds, fd_set * exceptfds,
	    const struct timespec *timeout, const sigset_t * sigmask)
{
	struct __pselect6 extended_sigmask = { sigmask, sizeof *sigmask };
	return __pselect6(n, readfds, writefds, exceptfds,
			  timeout, &extended_sigmask);
}
