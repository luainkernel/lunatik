/*
 * fopen.c
 */

#include "stdioint.h"

static int __parse_open_mode(const char *mode)
{
	int rwflags = O_RDONLY;
	int crflags = 0;
	int eflags  = 0;

	while (*mode) {
		switch (*mode++) {
		case 'r':
			rwflags = O_RDONLY;
			crflags = 0;
			break;
		case 'w':
			rwflags = O_WRONLY;
			crflags = O_CREAT | O_TRUNC;
			break;
		case 'a':
			rwflags = O_WRONLY;
			crflags = O_CREAT | O_APPEND;
			break;
		case 'e':
			eflags |= O_CLOEXEC;
			break;
		case 'x':
			eflags |= O_EXCL;
			break;
		case '+':
			rwflags = O_RDWR;
			break;
		}
	}

	return rwflags | crflags | eflags;
}

FILE *fopen(const char *file, const char *mode)
{
	int flags = __parse_open_mode(mode);
	int fd, err;
	FILE *f;

	fd = open(file, flags, 0666);
	if (fd < 0)
		return NULL;

	f = fdopen(fd, mode);
	if (!f) {
		err = errno;
		close(fd);
		errno = err;
	}
	return f;
}
