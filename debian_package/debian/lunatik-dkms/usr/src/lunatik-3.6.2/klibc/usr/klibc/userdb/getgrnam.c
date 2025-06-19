/*
 * getgrnam.c
 *
 * Dummy getgrnam() to support udev
 */

#include <grp.h>

#include "userdb.h"

struct group *getgrnam(const char *name)
{
	if (!strcmp(name, "root"))
		return (struct group *)&__root_group;

	errno = ENOENT;
	return NULL;
}
