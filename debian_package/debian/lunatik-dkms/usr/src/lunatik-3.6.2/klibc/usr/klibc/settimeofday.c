#include <time.h>
#include <sys/time.h>
#include <sys/syscall.h>

extern int __settimeofday(const void *, const struct timezone *);

int settimeofday(const struct timeval *tv, const struct timezone *tz)
{
	struct timespec ts;

	if (tz && __settimeofday(NULL, tz))
		return -1;

	if (tv) {
		ts.tv_sec = tv->tv_sec;
		ts.tv_nsec = tv->tv_usec * 1000;
		if (clock_settime(CLOCK_REALTIME, &ts))
			return -1;
	}

	return 0;
}
