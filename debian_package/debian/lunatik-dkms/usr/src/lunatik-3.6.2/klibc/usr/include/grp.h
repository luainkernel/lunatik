/*
 * grp.h
 */

#ifndef _GRP_H
#define _GRP_H

#include <klibc/extern.h>
#include <sys/types.h>

struct group {
	char *gr_name;
	char *gr_passwd;
	gid_t gr_gid;
	char **gr_mem;
};

__extern int setgroups(size_t, const gid_t *);
__extern struct group *getgrgid(gid_t);
__extern struct group *getgrnam(const char *);

#endif				/* _GRP_H */
