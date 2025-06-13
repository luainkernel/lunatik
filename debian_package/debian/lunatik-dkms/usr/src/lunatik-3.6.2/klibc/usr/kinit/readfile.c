/*
 * Read the entire contents of a file into malloc'd storage.  This
 * is mostly useful for things like /proc files where we can't just
 * fstat() to get the length and then mmap().
 *
 * Returns the number of bytes read, or -1 on error.
 */

#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <sys/stat.h>

#include "kinit.h"

ssize_t freadfile(FILE *f, char **pp)
{
	size_t bs;		/* Decent starting point... */
	size_t bf;		/* Bytes free */
	size_t bu = 0;		/* Bytes used */
	char *buffer, *nb;
	size_t rv;
	int old_errno = errno;

	bs = BUFSIZ;		/* A guess as good as any */
	bf = bs;
	buffer = malloc(bs);

	if (!buffer)
		return -1;

	for (;;) {
		errno = 0;

		while (bf && (rv = _fread(buffer + bu, bf, f))) {
			bu += rv;
			bf -= rv;
		}

		if (errno && errno != EINTR && errno != EAGAIN) {
			/* error */
			free(buffer);
			return -1;
		}

		if (bf) {
			/* Hit EOF, no error */

			/* Try to free superfluous memory */
			if ((nb = realloc(buffer, bu + 1)))
				buffer = nb;

			/* Null-terminate result for good measure */
			buffer[bu] = '\0';

			*pp = buffer;
			errno = old_errno;
			return bu;
		}

		/* Double the size of the buffer */
		bf += bs;
		bs += bs;
		if (!(nb = realloc(buffer, bs))) {
			/* out of memory error */
			free(buffer);
			return -1;
		}
		buffer = nb;
	}
}

ssize_t readfile(const char *filename, char **pp)
{
	FILE *f = fopen(filename, "r");
	ssize_t rv;

	if (!f)
		return -1;

	rv = freadfile(f, pp);

	fclose(f);

	return rv;
}
