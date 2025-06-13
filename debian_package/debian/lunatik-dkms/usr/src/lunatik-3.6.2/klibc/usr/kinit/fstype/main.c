/*
 * by rmk
 *
 * Detect filesystem type (on stdin) and output strings for two
 * environment variables:
 *  FSTYPE - filesystem type
 *  FSSIZE - filesystem size (if known)
 *
 * We currently detect (in order):
 *  gzip, cramfs, romfs, xfs, minix, ext3, ext2, reiserfs, jfs
 *
 * MINIX, ext3 and Reiserfs bits are currently untested.
 */

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include "fstype.h"

char *progname;

int main(int argc, char *argv[])
{
	int fd = 0;
	int rv;
	const char *fstype;
	const char *file = "stdin";
	unsigned long long bytes;

	progname = argv[0];

	if (argc > 2) {
		fprintf(stderr, "Usage: %s [file]\n", progname);
		return 1;
	}

	if (argc > 1 && !(argv[1][0] == '-' && argv[1][1] == '\0')) {
		fd = open(file = argv[1], O_RDONLY);
		if (fd < 0) {
			perror(argv[1]);
			return 2;
		}
	}

	rv = identify_fs(fd, &fstype, &bytes, 0);
	if (rv == -1) {
		perror(file);
		return 2;
	}

	fstype = fstype ? fstype : "unknown";

	fprintf(stdout, "FSTYPE=%s\nFSSIZE=%llu\n", fstype, bytes);
	return rv;
}
