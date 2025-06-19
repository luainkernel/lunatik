#include <errno.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <mntent.h>

#include "do_mounts.h"
#include "kinit.h"
#include "fstype.h"
#include "zlib.h"

#ifndef MS_RELATIME
#  define MS_RELATIME	(1<<21)	/* Update atime relative to mtime/ctime. */
#endif

#ifndef MS_STRICTATIME
#  define MS_STRICTATIME	(1<<24) /* Always perform atime updates */
#endif

/*
 * The following mount option parsing was stolen from
 *
 *       usr/utils/mount_opts.c
 *
 * and adapted to add some later mount flags.
 */
#define ARRAY_SIZE(x)	(sizeof(x) / sizeof(x[0]))

struct mount_opts {
	const char str[16];
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


/* These must be in alphabetic order! */
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
	{"relatime", MS_RELATIME, MS_RELATIME, 0},
	{"remount", MS_TYPE, MS_REMOUNT, 0},
	{"ro", MS_RDONLY, MS_RDONLY, 0},
	{"rw", MS_RDONLY, 0, MS_RDONLY},
	{"strictatime", MS_STRICTATIME, MS_STRICTATIME, 0},
	{"suid", MS_NOSUID, 0, MS_NOSUID},
	{"sync", MS_SYNCHRONOUS, MS_SYNCHRONOUS, 0},
	{"verbose", MS_VERBOSE, MS_VERBOSE, 0},
};

/*
 * Append 's' to 'extra->str'.  's' is a mount option that can't be turned into
 * a flag.  Return 0 on success, -1 on error.
 */
static int add_extra_option(struct extra_opts *extra, char *s)
{
	int len = strlen(s);
	int newlen = extra->used_size + len;

	if (extra->str)
		len++;		/* +1 for ',' */

	if (newlen >= extra->alloc_size) {
		char *new;

		new = realloc(extra->str, newlen + 1);	/* +1 for NUL */
		if (!new) {
			if (extra->str)
			       free(extra->str);
			return -1;
		}

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

	return 0;
}

/*
 * Parse the options in 'arg'; put numeric mount flags into 'flags' and
 * the rest into 'extra'.  Return 0 on success, -1 on error.
 */
static int
parse_mount_options(char *arg, unsigned long *flags, struct extra_opts *extra)
{
	char *s;

	while ((s = strsep(&arg, ",")) != NULL) {
		char *opt = s;
		unsigned int i;
		int res;
		int no = (s[0] == 'n' && s[1] == 'o');
		int found = 0;

		if (no)
			s += 2;

		for (i = 0; i < ARRAY_SIZE(options); i++) {

			res = strcmp(s, options[i].str);
			if (res == 0) {
				found = 1;
				*flags &= ~options[i].rwmask;
				if (no)
					*flags |= options[i].rwnoset;
				else
					*flags |= options[i].rwset;
				break;

			/* If we're beyond 's' alphabetically, we're done */
			} else if (res < 0)
				break;
		}
		if (! found)
			if (add_extra_option(extra, opt) != 0)
				return -1;
	}

	return 0;
}

/* Create the device node "name" */
int create_dev(const char *name, dev_t dev)
{
	unlink(name);
	return mknod(name, S_IFBLK | 0600, dev);
}


/*
 * If there is not a block device for the input 'name', try to create one; if
 * we can't that's okay.
 */
static void create_dev_if_not_present(const char *name)
{
	struct stat st;
	dev_t dev;

	if (stat(name, &st) == 0) /* file present; we're done */
		return;
	dev = name_to_dev_t(name);
	if (dev)
		(void) create_dev(name, dev);
}


/* mount a filesystem, possibly trying a set of different types */
const char *mount_block(const char *source, const char *target,
			const char *type, unsigned long flags,
			const void *data)
{
	char *fslist, *p, *ep;
	const char *rp;
	ssize_t fsbytes;
	int fd;

	if (type) {
		dprintf("kinit: trying to mount %s on %s "
			"with type %s, flags 0x%lx, data '%s'\n",
			source, target, type, flags, (char *)data);
		int rv = mount(source, target, type, flags, data);

		if (rv != 0)
			dprintf("kinit: mount %s on %s failed "
							"with errno = %d\n",
				source, target, errno);
		/* Mount readonly if necessary */
		if (rv == -1 && errno == EACCES && !(flags & MS_RDONLY))
			rv = mount(source, target, type, flags | MS_RDONLY,
				   data);
		return rv ? NULL : type;
	}

	/* If no type given, try to identify the type first; this
	   also takes care of specific ordering requirements, like
	   ext3 before ext2... */
	fd = open(source, O_RDONLY);
	if (fd >= 0) {
		int err = identify_fs(fd, &type, NULL, 0);
		close(fd);

		if (!err && type) {
			dprintf("kinit: %s appears to be a %s filesystem\n",
				source, type);
			type = mount_block(source, target, type, flags, data);
			if (type)
				return type;
		}
	}

	dprintf("kinit: failed to identify filesystem %s, trying all\n",
		source);

	fsbytes = readfile("/proc/filesystems", &fslist);

	errno = EINVAL;
	if (fsbytes < 0)
		return NULL;

	p = fslist;
	ep = fslist + fsbytes;

	rp = NULL;

	while (p < ep) {
		type = p;
		p = strchr(p, '\n');
		if (!p)
			break;
		*p++ = '\0';
		/* We can't mount a block device as a "nodev" fs */
		if (*type != '\t')
			continue;

		type++;
		rp = mount_block(source, target, type, flags, data);
		if (rp)
			break;
		if (errno != EINVAL)
			break;
	}

	free(fslist);
	return rp;
}

/* mount the root filesystem from a block device */
static int
mount_block_root(int argc, char *argv[], dev_t root_dev,
		 const char *type, unsigned long flags)
{
	const char *data, *rp;

	data = get_arg(argc, argv, "rootflags=");
	create_dev("/dev/root", root_dev);

	errno = 0;

	if (type) {
		if ((rp = mount_block("/dev/root", "/root", type, flags, data)))
			goto ok;
		if (errno != EINVAL)
			goto bad;
	}

	if (!errno
	    && (rp = mount_block("/dev/root", "/root", NULL, flags, data)))
		goto ok;

bad:
	if (errno != EINVAL) {
		/*
		 * Allow the user to distinguish between failed open
		 * and bad superblock on root device.
		 */
		fprintf(stderr, "%s: Cannot open root device %s\n",
			progname, bdevname(root_dev));
		return -errno;
	} else {
		fprintf(stderr, "%s: Unable to mount root fs on device %s\n",
			progname, bdevname(root_dev));
		return -ESRCH;
	}

ok:
	printf("%s: Mounted root (%s filesystem)%s.\n",
	       progname, rp, (flags & MS_RDONLY) ? " readonly" : "");
	return 0;
}

static int
mount_roots(int argc, char *argv[], const char *root_dev_name)
{
	char *roots = strdup(root_dev_name);
	char *root;
	const char *sep = ",";
	char *saveptr;
	int ret = -ESRCH;

	root = strtok_r(roots, sep, &saveptr);
	while (root) {
		dev_t root_dev;

		dprintf("kinit: trying to mount %s\n", root);
		root_dev = name_to_dev_t(root);
		ret = mount_root(argc, argv, root_dev, root);
		if (!ret)
			break;
		root = strtok_r(NULL, sep, &saveptr);
	}
	free(roots);
	return ret;
}

int
mount_root(int argc, char *argv[], dev_t root_dev, const char *root_dev_name)
{
	unsigned long flags = MS_RDONLY | MS_VERBOSE;
	int ret;
	const char *type = get_arg(argc, argv, "rootfstype=");

	if (get_flag(argc, argv, "rw") > get_flag(argc, argv, "ro")) {
		dprintf("kinit: mounting root rw\n");
		flags &= ~MS_RDONLY;
	}

	if (type) {
		if (!strcmp(type, "nfs"))
			root_dev = Root_NFS;
		else if (!strcmp(type, "jffs2") && !major(root_dev))
			root_dev = Root_MTD;
	}

	switch (root_dev) {
	case Root_NFS:
		ret = mount_nfs_root(argc, argv, flags);
		break;
	case Root_MTD:
		ret = mount_mtd_root(argc, argv, root_dev_name, type, flags);
		break;
	default:
		ret = mount_block_root(argc, argv, root_dev, type, flags);
		break;
	}

	if (!ret)
		chdir("/root");

	return ret;
}

/* Allocate a buffer and prepend '/root' onto 'src'. */
static char *prepend_root_dir(const char *src)
{
	size_t len = strlen(src) + 6;  /* "/root" */
	char *p = malloc(len);

	if (!p)
		return NULL;

	strcpy(p, "/root");
	strcat(p, src);
	return p;
}

int do_cmdline_mounts(int argc, char *argv[])
{
	int arg_i;
	int ret = 0;

	for (arg_i = 0; arg_i < argc; arg_i++) {
		const char *fs_dev, *fs_dir, *fs_type;
		char *fs_opts;
		unsigned long flags = 0;
		char *saveptr = NULL;
		char *new_dir;
		struct extra_opts extra = { 0, 0, 0, 0 };

		if (strncmp(argv[arg_i], "kinit_mount=", 12))
			continue;
		/*
		 * Format:
		 *   <fs_dev>;<dir>;<fs_type>;[opt1],[optn...]
		 */
		fs_dev = strtok_r(&argv[arg_i][12], ";", &saveptr);
		if (!fs_dev) {
			fprintf(stderr, "Failed to parse fs_dev\n");
			continue;
		}
		fs_dir = strtok_r(NULL, ";", &saveptr);
		if (!fs_dir) {
			fprintf(stderr, "Failed to parse fs_dir\n");
			continue;
		}
		fs_type = strtok_r(NULL, ";", &saveptr);
		if (!fs_type) {
			fprintf(stderr, "Failed to parse fs_type\n");
			continue;
		}
		fs_opts = strtok_r(NULL, ";", &saveptr);
		/* Don't error if there is no option string sent */

		new_dir = prepend_root_dir(fs_dir);
		if (! new_dir)
			return -ENOMEM;
		create_dev_if_not_present(fs_dev);
		ret = parse_mount_options(fs_opts, &flags, &extra);
		if (ret != 0)
			break;

		if (!mount_block(fs_dev, new_dir, fs_type,
				 flags, extra.str))
			fprintf(stderr, "Skipping failed mount '%s'\n", fs_dev);
		free(new_dir);
		if (extra.str)
			free(extra.str);
	}
	return ret;
}

int do_fstab_mounts(FILE *fp)
{
	struct mntent *ent = NULL;
	char *new_dir;
	int ret = 0;

	while ((ent = getmntent(fp))) {
		unsigned long flags = 0;
		struct extra_opts extra = { 0, 0, 0, 0 };

		new_dir = prepend_root_dir(ent->mnt_dir);
		if (! new_dir)
			return -ENOMEM;
		create_dev_if_not_present(ent->mnt_fsname);
		ret = parse_mount_options(ent->mnt_opts, &flags, &extra);
		if (ret != 0)
			break;

		if (!mount_block(ent->mnt_fsname,
				 new_dir,
				 ent->mnt_type,
				 flags,
				 extra.str)) {
			fprintf(stderr, "Skipping failed mount '%s'\n",
				ent->mnt_fsname);
		}
		free(new_dir);
		if (extra.str)
			free(extra.str);
	}
	return 0;
}

int do_mounts(int argc, char *argv[])
{
	const char *root_dev_name = get_arg(argc, argv, "root=");
	const char *root_delay = get_arg(argc, argv, "rootdelay=");
	const char *load_ramdisk = get_arg(argc, argv, "load_ramdisk=");
	dev_t root_dev = 0;
	int err;
	FILE *fp;

	dprintf("kinit: do_mounts\n");

	if (root_delay) {
		int delay = atoi(root_delay);
		fprintf(stderr, "Waiting %d s before mounting root device...\n",
			delay);
		sleep(delay);
	}

	md_run(argc, argv);

	if (root_dev_name) {
		root_dev = name_to_dev_t(root_dev_name);
	} else if (get_arg(argc, argv, "nfsroot=") ||
		   get_arg(argc, argv, "nfsaddrs=")) {
		root_dev = Root_NFS;
	} else {
		long rootdev;
		getintfile("/proc/sys/kernel/real-root-dev", &rootdev);
		root_dev = (dev_t) rootdev;
	}

	dprintf("kinit: root_dev = %s\n", bdevname(root_dev));

	if (initrd_load(argc, argv, root_dev)) {
		dprintf("initrd loaded\n");
		return 0;
	}

	if (load_ramdisk && atoi(load_ramdisk)) {
		if (ramdisk_load(argc, argv))
			root_dev = Root_RAM0;
	}

	if (root_dev == Root_MULTI)
		err = mount_roots(argc, argv, root_dev_name);
	else
		err = mount_root(argc, argv, root_dev, root_dev_name);

	if (err)
		return err;

	if ((fp = setmntent("/etc/fstab", "r"))) {
		err = do_fstab_mounts(fp);
		fclose(fp);
	}

	if (err)
		return err;

	if (get_arg(argc, argv, "kinit_mount="))
		err = do_cmdline_mounts(argc, argv);
	return err;
}
