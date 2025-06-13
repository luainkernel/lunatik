/*
 * Mount an MTD device as a character device.
 */

#include <errno.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>

#include "kinit.h"
#include "do_mounts.h"

int mount_mtd_root(int argc, char *argv[], const char *root_dev_name,
		   const char *type, unsigned long flags)
{
	const char *data = get_arg(argc, argv, "rootflags=");

	if (!type)
		type = "jffs2";

	printf("Trying to mount MTD %s as root (%s filesystem)\n",
		root_dev_name, type);

	if (mount(root_dev_name, "/root", type, flags, data)) {
		int err = errno;
		fprintf(stderr,
			"%s: Unable to mount MTD %s (%s filesystem) "
			"as root: %s\n",
			progname, root_dev_name, type, strerror(err));
		return -err;
	} else {
		fprintf(stderr, "%s: Mounted root (%s filesystem)%s.\n",
			progname, type, (flags & MS_RDONLY) ? " readonly" : "");
		return 0;
	}

}
