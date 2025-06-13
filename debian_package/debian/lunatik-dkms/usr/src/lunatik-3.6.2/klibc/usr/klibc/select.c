#include <sys/time.h>
#include <sys/types.h>
#include <sys/select.h>
#include <errno.h>
#include <sys/syscall.h>

struct __pselect6;
__extern int __pselect6(int, fd_set *, fd_set *, fd_set *,
			const struct timespec *, const struct __pselect6 *);

int select(int nfds, fd_set *readfds, fd_set *writefds,
	   fd_set *exceptfds, struct timeval *timeout)
{
	int result;
	struct timespec ts;

	if (timeout) {
		ts.tv_sec = timeout->tv_sec;
		ts.tv_nsec = timeout->tv_usec * 1000;
	}

	result = __pselect6(nfds, readfds, writefds, exceptfds,
			    timeout ? &ts : NULL, NULL);

	if (timeout) {
		timeout->tv_sec = ts.tv_sec;
		timeout->tv_usec = ts.tv_nsec / 1000;
	}

	return result;
}
