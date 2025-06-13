/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2006 H. Peter Anvin - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * run_init(realroot, consoledev, drop_caps, persist_initramfs, init, initargs)
 *
 * This function should be called as the last thing in kinit,
 * from initramfs, it does the following:
 *
 * - Delete all files in the initramfs;
 * - Remounts /real-root onto the root filesystem;
 * - Chroots;
 * - Drops comma-separated list of capabilities;
 * - Opens /dev/console;
 * - Spawns the specified init program (with arguments.)
 *
 * On failure, returns a human-readable error message.
 */

#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/vfs.h>
#include "run-init.h"
#include "capabilities.h"

/* Make it possible to compile on glibc by including constants that the
   always-behind shipped glibc headers may not include.  Classic example
   on why the lack of ABI headers screw us up. */
#ifndef TMPFS_MAGIC
# define TMPFS_MAGIC	0x01021994
#endif
#ifndef RAMFS_MAGIC
# define RAMFS_MAGIC	0x858458f6
#endif
#ifndef MS_MOVE
# define MS_MOVE	8192
#endif

static int nuke(const char *what);

static int nuke_dirent(int len, const char *dir, const char *name, dev_t me)
{
	int bytes = len + strlen(name) + 2;
	char path[bytes];
	int xlen;
	struct stat st;

	xlen = snprintf(path, bytes, "%s/%s", dir, name);
	assert(xlen < bytes);

	if (lstat(path, &st))
		return ENOENT;	/* Return 0 since already gone? */

	if (st.st_dev != me)
		return 0;	/* DO NOT recurse down mount points!!!!! */

	return nuke(path);
}

/* Wipe the contents of a directory, but not the directory itself */
static int nuke_dir(const char *what)
{
	int len = strlen(what);
	DIR *dir;
	struct dirent *d;
	int err = 0;
	struct stat st;

	if (lstat(what, &st))
		return errno;

	if (!S_ISDIR(st.st_mode))
		return ENOTDIR;

	if (!(dir = opendir(what))) {
		/* EACCES means we can't read it.  Might be empty and removable;
		   if not, the rmdir() in nuke() will trigger an error. */
		return (errno == EACCES) ? 0 : errno;
	}

	while ((d = readdir(dir))) {
		/* Skip . and .. */
		if (d->d_name[0] == '.' &&
		    (d->d_name[1] == '\0' ||
		     (d->d_name[1] == '.' && d->d_name[2] == '\0')))
			continue;

		err = nuke_dirent(len, what, d->d_name, st.st_dev);
		if (err) {
			closedir(dir);
			return err;
		}
	}

	closedir(dir);

	return 0;
}

static int nuke(const char *what)
{
	int rv;
	int err = 0;

	rv = unlink(what);
	if (rv < 0) {
		if (errno == EISDIR) {
			/* It's a directory. */
			err = nuke_dir(what);
			if (!err)
				err = rmdir(what) ? errno : err;
		} else {
			err = errno;
		}
	}

	if (err) {
		errno = err;
		return err;
	} else {
		return 0;
	}
}

const char *run_init(const char *realroot, const char *console,
		     const char *drop_caps, bool dry_run,
		     bool persist_initramfs, const char *init, char **initargs)
{
	struct stat rst, cst, ist;
	struct statfs sfs;
	int confd;

	/* First, change to the new root directory */
	if (chdir(realroot))
		return "chdir to new root";

	/* This is a potentially highly destructive program.  Take some
	   extra precautions. */

	/* Make sure the current directory is not on the same filesystem
	   as the root directory */
	if (stat("/", &rst) || stat(".", &cst))
		return "stat";

	if (rst.st_dev == cst.st_dev)
		return "current directory on the same filesystem as the root";

	/* Make sure we're on a ramfs */
	if (statfs("/", &sfs))
		return "statfs /";
	if (sfs.f_type != RAMFS_MAGIC && sfs.f_type != TMPFS_MAGIC)
		return "rootfs not a ramfs or tmpfs";

	/* Okay, I think we should be safe... */

	if (!dry_run) {
		if (!persist_initramfs) {
			/* Delete rootfs contents */
			if (nuke_dir("/"))
				return "nuking initramfs contents";
		}

		/* Overmount the root */
		if (mount(".", "/", NULL, MS_MOVE, NULL))
			return "overmounting root";
	}

	/* chroot, chdir */
	if (chroot(".") || chdir("/"))
		return "chroot";

	/* Drop capabilities */
	if (drop_capabilities(drop_caps) < 0)
		return "dropping capabilities";

	/* Open /dev/console */
	if ((confd = open(console, O_RDWR)) < 0)
		return "opening console";
	if (!dry_run) {
		dup2(confd, 0);
		dup2(confd, 1);
		dup2(confd, 2);
	}
	close(confd);

	if (!dry_run) {
		/* Spawn init */
		execv(init, initargs);
		return init;		/* Failed to spawn init */
	} else {
		if (stat(init, &ist))
			return init;
		if (!S_ISREG(ist.st_mode) || !(ist.st_mode & S_IXUGO)) {
			errno = EACCES;
			return init;
		}
		return NULL;		/* Success */
	}
}
