/*
 * Simple test of select()
 */

#include <sys/select.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
	int fdn, fdz, pfd[2], rv;
	fd_set readset;
	struct timeval timeout;
	int err = 0;

	/* We can always read from /dev/zero; open a pipe that is never
	   ready for a "never readable" file descriptor */
	fdz = open("/dev/zero", O_RDONLY);
	pipe(pfd);
	fdn = pfd[0];

	FD_ZERO(&readset);
	FD_SET(fdn, &readset);

	timeout.tv_sec = 0;
	timeout.tv_usec = 100000;

	rv = select(FD_SETSIZE, &readset, NULL, NULL, &timeout);

	if (rv != 0) {
		fprintf(stderr,
			"select with timeout failed (rv = %d, errno = %s)\n",
			rv, strerror(errno));
		err++;
	}

	FD_ZERO(&readset);
	FD_SET(fdn, &readset);
	FD_SET(fdz, &readset);

	rv = select(FD_SETSIZE, &readset, NULL, NULL, &timeout);

	if (rv != 1 || !FD_ISSET(fdz, &readset) ||
	    FD_ISSET(fdn, &readset)) {
		fprintf(stderr,
			"select with /dev/zero failed (rv = %d, errno = %s)\n",
			rv, strerror(errno));
		err++;
	}

	return err;
}
