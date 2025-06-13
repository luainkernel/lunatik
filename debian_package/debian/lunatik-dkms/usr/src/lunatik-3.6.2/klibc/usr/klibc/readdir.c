/*
 * readdir.c: opendir/readdir/closedir
 */

#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <errno.h>

#define __KLIBC_DIRENT_INTERNALS
#include <dirent.h>

DIR *fdopendir(int fd)
{
	DIR *dp = zalloc(sizeof(DIR));

	if (!dp)
		return NULL;

	dp->__fd = fd;
	return dp;
}

DIR *opendir(const char *name)
{
	int fd, err;
	DIR *dp;

	fd = open(name, O_DIRECTORY | O_RDONLY);
	if (fd < 0)
		return NULL;

	dp = fdopendir(fd);
	if (!dp) {
		err = errno;
		close(fd);
		errno = err;
	}
	return dp;
}

struct dirent *readdir(DIR *dir)
{
	struct dirent *dent;
	int rv;

	if (!dir->bytes_left) {
		rv = getdents(dir->__fd, dir->buffer, sizeof(dir->buffer));
		if (rv <= 0)
			return NULL;
		dir->bytes_left = rv;
		dir->next = dir->buffer;
	}

	dent = dir->next;
	dir->next = (struct dirent *)((char *)dir->next + dent->d_reclen);
	dir->bytes_left -= dent->d_reclen;

	return dent;
}

int closedir(DIR *dir)
{
	int rv;
	rv = close(dir->__fd);
	free(dir);
	return rv;
}
