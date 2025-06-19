#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <sys/stat.h>
#include <linux/fs.h>
#include <linux/cdrom.h>
#include <linux/fd.h>

#include "kinit.h"
#include "do_mounts.h"
#include "fstype.h"
#include "zlib.h"

#define BUF_SZ		65536

static void wait_for_key(void)
{
	/* Wait until the user presses Enter */
	while (getchar() != '\n')
		;
}

static int change_disk(const char *devpath, int rfd, int disk)
{
	/* Try to eject and/or quiesce the device */
	sync();
	if (ioctl(rfd, FDEJECT, 0)) {
		if (errno == ENOTTY) {
			/* Not a floppy */
			ioctl(rfd, CDROMEJECT, 0);
		} else {
			/* Non-ejectable floppy */
			ioctl(rfd, FDRESET, (void *)FD_RESET_IF_NEEDED);
		}
	}
	close(rfd);

	fprintf(stderr,
		"\nPlease insert disk %d for ramdisk and press Enter...", disk);
	wait_for_key();

	return open(devpath, O_RDONLY);
}

#ifdef CONFIG_KLIBC_ZLIB
/* Also used in initrd.c */
int load_ramdisk_compressed(const char *devpath, FILE * wfd,
			    off_t ramdisk_start)
{
	int rfd = -1;
	unsigned long long ramdisk_size, ramdisk_left;
	int disk = 1;
	ssize_t bytes;
	int rv;
	unsigned char in_buf[BUF_SZ], out_buf[BUF_SZ];
	z_stream zs;

	zs.zalloc = Z_NULL;	/* Use malloc() */
	zs.zfree = Z_NULL;	/* Use free() */
	zs.next_in = Z_NULL;	/* No data read yet */
	zs.avail_in = 0;
	zs.next_out = out_buf;
	zs.avail_out = BUF_SZ;

	if (inflateInit2(&zs, 32 + 15) != Z_OK)
		goto err1;

	rfd = open(devpath, O_RDONLY);
	if (rfd < 0)
		goto err2;

	/* Set to the size of the medium, or "infinite" */
	if (ioctl(rfd, BLKGETSIZE64, &ramdisk_size))
		ramdisk_size = ~0ULL;

	do {
		/* Purge the output preferentially over reading new
		   input, so we don't end up overrunning the input by
		   accident and demanding a new disk which doesn't
		   exist... */
		if (zs.avail_out == 0) {
			_fwrite(out_buf, BUF_SZ, wfd);
			zs.next_out = out_buf;
			zs.avail_out = BUF_SZ;
		} else if (zs.avail_in == 0) {
			if (ramdisk_start >= ramdisk_size) {
				rfd = change_disk(devpath, rfd, ++disk);
				if (rfd < 0)
					goto err2;

				if (ioctl(rfd, BLKGETSIZE64, &ramdisk_size))
					ramdisk_size = ~0ULL;
				ramdisk_start = 0;
				dprintf("New size = %llu\n", ramdisk_size);
			}
			do {
				ramdisk_left = ramdisk_size - ramdisk_start;
				bytes = min(ramdisk_left,
					    (unsigned long long)BUF_SZ);
				bytes = pread(rfd, in_buf, bytes,
					      ramdisk_start);
			} while (bytes == -1 && errno == EINTR);
			if (bytes <= 0)
				goto err2;
			ramdisk_start += bytes;
			zs.next_in = in_buf;
			zs.avail_in = bytes;

			/* Print dots if we're reading from a real block device */
			if (ramdisk_size != ~0ULL)
				putc('.', stderr);
		}
		rv = inflate(&zs, Z_SYNC_FLUSH);
	} while (rv == Z_OK || rv == Z_BUF_ERROR);

	dprintf("kinit: inflate returned %d\n", rv);

	if (rv != Z_STREAM_END)
		goto err2;

	/* Write the last */
	_fwrite(out_buf, BUF_SZ - zs.avail_out, wfd);
	dprintf("kinit: writing %d bytes\n", BUF_SZ - zs.avail_out);

	inflateEnd(&zs);
	return 0;

err2:
	inflateEnd(&zs);
err1:
	return -1;
}
#else
int load_ramdisk_compressed(const char *devpath, FILE * wfd,
			    off_t ramdisk_start)
{
	fprintf(stderr, "Compressed ramdisk not supported\n");
	return -1;
}
#endif

static int
load_ramdisk_raw(const char *devpath, FILE * wfd, off_t ramdisk_start,
		 unsigned long long fssize)
{
	unsigned long long ramdisk_size, ramdisk_left;
	int disk = 1;
	ssize_t bytes;
	unsigned char buf[BUF_SZ];
	int rfd;

	rfd = open(devpath, O_RDONLY);
	if (rfd < 0)
		return -1;

	/* Set to the size of the medium, or "infinite" */
	if (ioctl(rfd, BLKGETSIZE64, &ramdisk_size))
		ramdisk_size = ~0ULL;

	dprintf("start: %llu  size: %llu  fssize: %llu\n",
		ramdisk_start, ramdisk_size, fssize);

	while (fssize) {

		if (ramdisk_start >= ramdisk_size) {
			rfd = change_disk(devpath, rfd, ++disk);
			if (rfd < 0)
				return -1;

			if (ioctl(rfd, BLKGETSIZE64, &ramdisk_size))
				ramdisk_size = ~0ULL;
			ramdisk_start = 0;
		}

		do {
			ramdisk_left =
			    min(ramdisk_size - ramdisk_start, fssize);
			bytes = min(ramdisk_left, (unsigned long long)BUF_SZ);
			bytes = pread(rfd, buf, bytes, ramdisk_start);
		} while (bytes == -1 && errno == EINTR);
		if (bytes <= 0)
			break;
		_fwrite(buf, bytes, wfd);

		ramdisk_start += bytes;
		fssize -= bytes;

		/* Print dots if we're reading from a real block device */
		if (ramdisk_size != ~0ULL)
			putc('.', stderr);
	}

	return !!fssize;
}

int ramdisk_load(int argc, char *argv[])
{
	const char *arg_prompt_ramdisk = get_arg(argc, argv, "prompt_ramdisk=");
	const char *arg_ramdisk_blocksize =
	    get_arg(argc, argv, "ramdisk_blocksize=");
	const char *arg_ramdisk_start = get_arg(argc, argv, "ramdisk_start=");
	const char *arg_ramdisk_device = get_arg(argc, argv, "ramdisk_device=");

	int prompt_ramdisk = arg_prompt_ramdisk ? atoi(arg_prompt_ramdisk) : 0;
	int ramdisk_blocksize =
	    arg_ramdisk_blocksize ? atoi(arg_ramdisk_blocksize) : 512;
	off_t ramdisk_start =
	    arg_ramdisk_start
	    ? strtoumax(arg_ramdisk_start, NULL, 10) * ramdisk_blocksize : 0;
	const char *ramdisk_device =
	    arg_ramdisk_device ? arg_ramdisk_device : "/dev/fd0";

	dev_t ramdisk_dev;
	int rfd;
	FILE *wfd;
	const char *fstype;
	unsigned long long fssize;
	int is_gzip = 0;
	int err;

	if (prompt_ramdisk) {
		fprintf(stderr,
			"Please insert disk for ramdisk and press Enter...");
		wait_for_key();
	}

	ramdisk_dev = name_to_dev_t(ramdisk_device);
	if (!ramdisk_dev) {
		fprintf(stderr,
			"Failure loading ramdisk: unknown device: %s\n",
			ramdisk_device);
		return 0;
	}

	create_dev("/dev/rddev", ramdisk_dev);
	create_dev("/dev/ram0", Root_RAM0);
	rfd = open("/dev/rddev", O_RDONLY);
	wfd = fopen("/dev/ram0", "w");

	if (rfd < 0 || !wfd) {
		perror("Could not open ramdisk device");
		return 0;
	}

	/* Check filesystem type */
	if (identify_fs(rfd, &fstype, &fssize, ramdisk_start) ||
	    (fssize == 0 && !(is_gzip = !strcmp(fstype, "gzip")))) {
		fprintf(stderr,
			"Failure loading ramdisk: unknown filesystem type\n");
		close(rfd);
		fclose(wfd);
		return 0;
	}

	dprintf("kinit: ramdisk is %s, size %llu\n", fstype, fssize);

	fprintf(stderr, "Loading ramdisk (%s) ...", is_gzip ? "gzip" : "raw");

	close(rfd);

	if (is_gzip)
		err = load_ramdisk_compressed("/dev/rddev", wfd, ramdisk_start);
	else
		err = load_ramdisk_raw("/dev/rddev", wfd,
				       ramdisk_start, fssize);

	fclose(wfd);

	putc('\n', stderr);

	if (err) {
		perror("Failure loading ramdisk");
		return 0;
	}

	return 1;
}
