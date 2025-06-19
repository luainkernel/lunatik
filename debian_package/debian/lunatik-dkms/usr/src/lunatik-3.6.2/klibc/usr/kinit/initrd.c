/*
 * Handle initrd, thus putting the backwards into backwards compatible
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include "do_mounts.h"
#include "kinit.h"
#include "xpio.h"

#define BUF_SIZE	65536	/* Should be a power of 2 */

/*
 * Copy the initrd to /dev/ram0, copy from the end to the beginning
 * to avoid taking 2x the memory.
 */
static int rd_copy_uncompressed(int ffd, int dfd)
{
	char buffer[BUF_SIZE];
	off_t bytes;
	struct stat st;

	dprintf("kinit: uncompressed initrd\n");

	if (ffd < 0 || fstat(ffd, &st) || !S_ISREG(st.st_mode) ||
	    (bytes = st.st_size) == 0)
		return -1;

	while (bytes) {
		ssize_t blocksize = ((bytes - 1) & (BUF_SIZE - 1)) + 1;
		off_t offset = bytes - blocksize;

		dprintf("kinit: copying %zd bytes at offset %llu\n",
			blocksize, offset);

		if (xpread(ffd, buffer, blocksize, offset) != blocksize ||
		    xpwrite(dfd, buffer, blocksize, offset) != blocksize)
			return -1;

		ftruncate(ffd, offset);	/* Free up memory */
		bytes = offset;
	}
	return 0;
}

static int rd_copy_image(const char *path)
{
	int ffd = open(path, O_RDONLY);
	int rv = -1;
	unsigned char gzip_magic[2];

	if (ffd < 0)
		goto barf;

	if (xpread(ffd, gzip_magic, 2, 0) == 2 &&
	    gzip_magic[0] == 037 && gzip_magic[1] == 0213) {
		FILE *wfd = fopen("/dev/ram0", "w");
		if (!wfd)
			goto barf;
		rv = load_ramdisk_compressed(path, wfd, 0);
		fclose(wfd);
	} else {
		int dfd = open("/dev/ram0", O_WRONLY);
		if (dfd < 0)
			goto barf;
		rv = rd_copy_uncompressed(ffd, dfd);
		close(dfd);
	}

barf:
	if (ffd >= 0)
		close(ffd);
	return rv;
}

/*
 * Run /linuxrc, for emulation of old-style initrd
 */
static int run_linuxrc(int argc, char *argv[], dev_t root_dev)
{
	int root_fd, old_fd;
	pid_t pid;
	long realroot = Root_RAM0;
	const char *ramdisk_name = "/dev/ram0";
	FILE *fp;

	dprintf("kinit: mounting initrd\n");
	mkdir("/root", 0700);
	if (!mount_block(ramdisk_name, "/root", NULL, MS_VERBOSE, NULL))
		return -errno;

	/* Write the current "real root device" out to procfs */
	dprintf("kinit: real_root_dev = %#x\n", root_dev);
	fp = fopen("/proc/sys/kernel/real-root-dev", "w");
	fprintf(fp, "%u", root_dev);
	fclose(fp);

	mkdir("/old", 0700);
	root_fd = open("/", O_RDONLY|O_DIRECTORY|O_CLOEXEC, 0);
	old_fd = open("/old", O_RDONLY|O_DIRECTORY|O_CLOEXEC, 0);

	if (root_fd < 0 || old_fd < 0)
		return -errno;

	if (chdir("/root") ||
	    mount(".", "/", NULL, MS_MOVE, NULL) || chroot("."))
		return -errno;

	pid = vfork();
	if (pid == 0) {
		setsid();
		/* Looks like linuxrc doesn't get the init environment
		   or parameters.  Weird, but so is the whole linuxrc bit. */
		execl("/linuxrc", "linuxrc", NULL);
		_exit(255);
	} else if (pid > 0) {
		dprintf("kinit: Waiting for linuxrc to complete...\n");
		while (waitpid(pid, NULL, 0) != pid)
			;
		dprintf("kinit: linuxrc done\n");
	} else {
		return -errno;
	}

	if (fchdir(old_fd) ||
	    mount("/", ".", NULL, MS_MOVE, NULL) ||
	    fchdir(root_fd) || chroot("."))
		return -errno;

	close(root_fd);
	close(old_fd);

	getintfile("/proc/sys/kernel/real-root-dev", &realroot);

	/* If realroot is Root_RAM0, then the initrd did any necessary work */
	if (realroot == Root_RAM0) {
		if (mount("/old", "/root", NULL, MS_MOVE, NULL))
			return -errno;
	} else {
		mount_root(argc, argv, (dev_t) realroot, NULL);

		/* If /root/initrd exists, move the initrd there, otherwise discard */
		if (!mount("/old", "/root/initrd", NULL, MS_MOVE, NULL)) {
			/* We're good */
		} else {
			int olddev = open(ramdisk_name, O_RDWR);
			umount2("/old", MNT_DETACH);
			if (olddev < 0 ||
			    ioctl(olddev, BLKFLSBUF, 0) ||
			    close(olddev)) {
				fprintf(stderr,
					"%s: Cannot flush initrd contents\n",
					progname);
			}
		}
	}

	rmdir("/old");
	return 0;
}

int initrd_load(int argc, char *argv[], dev_t root_dev)
{
	if (access("/initrd.image", R_OK))
		return 0;	/* No initrd */

	dprintf("kinit: initrd found\n");

	create_dev("/dev/ram0", Root_RAM0);

	if (rd_copy_image("/initrd.image") || unlink("/initrd.image")) {
		fprintf(stderr, "%s: initrd installation failed (too big?)\n",
			progname);
		return 0;	/* Failed to copy initrd */
	}

	dprintf("kinit: initrd copied\n");

	if (root_dev == Root_MULTI) {
		dprintf("kinit: skipping linuxrc: incompatible with multiple roots\n");
		/* Mounting initrd as ordinary root */
		return 0;
	}

	if (root_dev != Root_RAM0) {
		int err;
		dprintf("kinit: running linuxrc\n");
		err = run_linuxrc(argc, argv, root_dev);
		if (err)
			fprintf(stderr, "%s: running linuxrc: %s\n", progname,
				strerror(-err));
		return 1;	/* initrd is root, or run_linuxrc took care of it */
	} else {
		dprintf("kinit: permament (or pivoting) initrd, not running linuxrc\n");
		return 0;	/* Mounting initrd as ordinary root */
	}
}
