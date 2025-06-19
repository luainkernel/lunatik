/*
 * usleep.c
 */

#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

void usleep(unsigned long usec)
{
	struct timespec ts;

	ts.tv_sec = usec / 1000000UL;
	ts.tv_nsec = (usec % 1000000UL) * 1000;
	while (nanosleep(&ts, &ts) == -1 && errno == EINTR) ;
}
