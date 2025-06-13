#include <time.h>
#include <sys/time.h>
#include <sys/syscall.h>

int nanosleep(const struct timespec *request, struct timespec *remain)
{
	return clock_nanosleep(CLOCK_MONOTONIC, 0, request, remain) ? -1 : 0;
}
