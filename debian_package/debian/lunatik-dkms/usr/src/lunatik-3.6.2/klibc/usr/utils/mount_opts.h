#ifndef UTILS_MOUNT_OPTS_H
#define UTILS_MOUNT_OPTS_H

struct mount_opts {
	const char str[8];
	unsigned long rwmask;
	unsigned long rwset;
	unsigned long rwnoset;
};

struct extra_opts {
	char *str;
	char *end;
	int used_size;
	int alloc_size;
};

/*
 * These options define the function of "mount(2)".
 */
#define MS_TYPE	(MS_REMOUNT|MS_BIND|MS_MOVE)

unsigned long
parse_mount_options(char *arg, unsigned long rwflag, struct extra_opts *extra);

#endif /* UTILS_MOUNT_OPTS_H */
