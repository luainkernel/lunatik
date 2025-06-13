#include <fcntl.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/syscall.h>

int utimes(const char *file, const struct timeval tvp[2])
{
	struct timespec ts[2];

	if (tvp) {
		ts[0].tv_sec = tvp[0].tv_sec;
		ts[0].tv_nsec = tvp[0].tv_usec * 1000;
		ts[1].tv_sec = tvp[1].tv_sec;
		ts[1].tv_nsec = tvp[1].tv_usec * 1000;
	}

	return utimensat(AT_FDCWD, file, &ts[0], 0);
}
