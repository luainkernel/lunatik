#include <fcntl.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/syscall.h>

int futimesat(int dirfd, const char *filename, const struct timeval tvp[2])
{
	struct timespec ts[2];

	if (tvp) {
		ts[0].tv_sec = tvp[0].tv_sec;
		ts[0].tv_nsec = tvp[0].tv_usec * 1000;
		ts[1].tv_sec = tvp[1].tv_sec;
		ts[1].tv_nsec = tvp[1].tv_usec * 1000;
	}

	return utimensat(dirfd, filename, &ts[0], 0);
}
