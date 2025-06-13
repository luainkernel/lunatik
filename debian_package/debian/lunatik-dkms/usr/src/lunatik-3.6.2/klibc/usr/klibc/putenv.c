/*
 * putenv.c
 */

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "env.h"

int putenv(const char *str)
{
	char *s;
	const char *e, *z;

	if (!str) {
		errno = EINVAL;
		return -1;
	}

	e = NULL;
	for (z = str; *z; z++) {
		if (*z == '=')
			e = z;
	}

	if (!e) {
		errno = EINVAL;
		return -1;
	}

	s = strdup(str);
	if (!s)
		return -1;

	return __put_env(s, e - str, 1);
}
