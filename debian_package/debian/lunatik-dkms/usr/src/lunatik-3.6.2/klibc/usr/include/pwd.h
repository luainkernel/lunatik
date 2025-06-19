#ifndef _PWD_H
#define _PWD_H

#include <klibc/extern.h>
#include <sys/types.h>

struct passwd {
	char *pw_name;
	char *pw_passwd;
	uid_t pw_uid;
	gid_t pw_gid;
	char *pw_gecos;
	char *pw_dir;
	char *pw_shell;
};

__extern struct passwd *getpwuid(uid_t uid);

__extern struct passwd *getpwnam(const char *name);

#endif	/* _PWD_H */
