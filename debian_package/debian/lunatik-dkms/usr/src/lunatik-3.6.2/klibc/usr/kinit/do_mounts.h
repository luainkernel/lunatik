/*
 * do_mounts.h
 */

#ifndef DO_MOUNTS_H
#define DO_MOUNTS_H

#include <sys/types.h>
#include <sys/sysmacros.h>
#include <sys/stat.h>

#define	Root_RAM0	__makedev(1, 0)

/* These device numbers are only used internally */
#define Root_NFS	__makedev(0, 255)
#define Root_MTD	__makedev(0, 254)
#define Root_MULTI	__makedev(0, 253)

int create_dev(const char *name, dev_t dev);

dev_t name_to_dev_t(const char *name);

const char *mount_block(const char *source, const char *target,
			const char *type, unsigned long flags,
			const void *data);

int mount_root(int argc, char *argv[], dev_t root_dev,
	       const char *root_dev_name);

int mount_mtd_root(int argc, char *argv[], const char *root_dev_name,
		   const char *type, unsigned long flags);

int do_mounts(int argc, char *argv[]);

int initrd_load(int argc, char *argv[], dev_t root_dev);

static inline dev_t bstat(const char *name)
{
	struct stat st;

	if (stat(name, &st) || !S_ISBLK(st.st_mode))
		return 0;
	return st.st_rdev;
}

int load_ramdisk_compressed(const char *devpath, FILE * wfd,
			    off_t ramdisk_start);

#endif				/* DO_MOUNTS_H */
