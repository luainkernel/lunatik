#include <time.h>
#include <sys/time.h>
#include <sys/syscall.h>

extern int __gettimeofday(void *, struct timezone *);

int gettimeofday(struct timeval *tv, struct timezone *tz)
{
	struct timespec ts;

	if (tv) {
		if (clock_gettime(CLOCK_REALTIME, &ts))
			return -1;
		tv->tv_sec = ts.tv_sec;
		tv->tv_usec = ts.tv_nsec / 1000;
	}

	if (tz && __gettimeofday(NULL, tz))
		return -1;

	return 0;
}
