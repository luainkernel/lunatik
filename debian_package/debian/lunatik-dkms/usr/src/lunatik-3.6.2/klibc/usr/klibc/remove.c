/*
 * remove.c
 */

#include <stdio.h>
#include <unistd.h>
#include <errno.h>

int remove(const char *pathname)
{
	int rv;

	rv = unlink(pathname);
	if (rv == -1 && errno == EISDIR)
		return rmdir(pathname);

	return rv;
}
