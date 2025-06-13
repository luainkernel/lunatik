/*
 * by rmk
 *
 * Decode mount options.
 */
#include <sys/mount.h>
#include <stdlib.h>
#include <string.h>

#include "mount_opts.h"

#define ARRAY_SIZE(x)	(sizeof(x) / sizeof(x[0]))

static const struct mount_opts options[] = {
	/* name         mask            set             noset           */
	{"async", MS_SYNCHRONOUS, 0, MS_SYNCHRONOUS},
	{"atime", MS_NOATIME, 0, MS_NOATIME},
	{"bind", MS_TYPE, MS_BIND, 0,},
	{"dev", MS_NODEV, 0, MS_NODEV},
	{"diratime", MS_NODIRATIME, 0, MS_NODIRATIME},
	{"dirsync", MS_DIRSYNC, MS_DIRSYNC, 0},
	{"exec", MS_NOEXEC, 0, MS_NOEXEC},
	{"move", MS_TYPE, MS_MOVE, 0},
	{"nodev", MS_NODEV, MS_NODEV, 0},
	{"noexec", MS_NOEXEC, MS_NOEXEC, 0},
	{"nosuid", MS_NOSUID, MS_NOSUID, 0},
	{"recurse", MS_REC, MS_REC, 0},
	{"remount", MS_TYPE, MS_REMOUNT, 0},
	{"ro", MS_RDONLY, MS_RDONLY, 0},
	{"rw", MS_RDONLY, 0, MS_RDONLY},
	{"suid", MS_NOSUID, 0, MS_NOSUID},
	{"sync", MS_SYNCHRONOUS, MS_SYNCHRONOUS, 0},
	{"verbose", MS_VERBOSE, MS_VERBOSE, 0},
};

static void add_extra_option(struct extra_opts *extra, char *s)
{
	int len = strlen(s);
	int newlen = extra->used_size + len;

	if (extra->str)
		len++;		/* +1 for ',' */

	if (newlen >= extra->alloc_size) {
		char *new;

		new = realloc(extra->str, newlen + 1);	/* +1 for NUL */
		if (!new)
			return;

		extra->str = new;
		extra->end = extra->str + extra->used_size;
		extra->alloc_size = newlen;
	}

	if (extra->used_size) {
		*extra->end = ',';
		extra->end++;
	}
	strcpy(extra->end, s);
	extra->used_size += len;

}

unsigned long
parse_mount_options(char *arg, unsigned long rwflag, struct extra_opts *extra)
{
	char *s;

	while ((s = strsep(&arg, ",")) != NULL) {
		char *opt = s;
		unsigned int i;
		int res, no = s[0] == 'n' && s[1] == 'o';

		if (no)
			s += 2;

		for (i = 0, res = 1; i < ARRAY_SIZE(options); i++) {
			res = strcmp(s, options[i].str);

			if (res == 0) {
				rwflag &= ~options[i].rwmask;
				if (no)
					rwflag |= options[i].rwnoset;
				else
					rwflag |= options[i].rwset;
			}
			if (res <= 0)
				break;
		}

		if (res != 0 && s[0]) {
			if (!strcmp(opt, "defaults"))
				rwflag &= ~(MS_RDONLY|MS_NOSUID|MS_NODEV|
					    MS_NOEXEC|MS_SYNCHRONOUS);
			else
				add_extra_option(extra, opt);
		}
	}

	return rwflag;
}
