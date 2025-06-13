/*
 * Looping versions of pread() and pwrite()
 */

#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

#include "xpio.h"

ssize_t xpread(int fd, void *buf, size_t count, off_t offset)
{
	ssize_t ctr = 0;
	ssize_t rv = 0;
	char *bp = buf;

	while (count) {
		rv = pread(fd, bp, count, offset);

		if (rv == 0 || (rv == -1 && errno != EINTR))
			break;

		bp	+= rv;
		count	-= rv;
		offset	+= rv;
		ctr	+= rv;
	}

	return ctr ? ctr : rv;
}

ssize_t xpwrite(int fd, void *buf, size_t count, off_t offset)
{
	ssize_t ctr = 0;
	ssize_t rv = 0;
	char *bp = buf;

	while (count) {
		rv = pwrite(fd, bp, count, offset);

		if (rv == 0 || (rv == -1 && errno != EINTR))
			break;

		bp	+= rv;
		count	-= rv;
		offset	+= rv;
		ctr	+= rv;
	}

	return ctr ? ctr : rv;
}
