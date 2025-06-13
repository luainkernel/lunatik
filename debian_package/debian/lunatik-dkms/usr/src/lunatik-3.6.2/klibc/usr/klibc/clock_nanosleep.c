#include <time.h>
#include <sys/time.h>
#include <sys/syscall.h>

extern int __clock_nanosleep(clockid_t, int,
			     const struct timespec *, struct timespec *);

/*
 * POSIX says this has to return a positive error code, but the system
 * call returns error codes in the usual way.
 */
int clock_nanosleep(clockid_t clock_id, int flags,
		    const struct timespec *request, struct timespec *remain)
{
	return __clock_nanosleep(clock_id, flags, request, remain) ?
		errno : 0;
}
