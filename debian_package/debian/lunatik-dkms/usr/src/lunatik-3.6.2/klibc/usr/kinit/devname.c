#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <sys/types.h>
#include <sys/sysmacros.h>

#include "kinit.h"

/*
 * Print the name of a block device.
 */
#define BUF_SIZE	512

static int scansysdir(char *namebuf, char *sysdir, dev_t dev)
{
	char *dirtailptr = strchr(sysdir, '\0');
	DIR *dir;
	int done = 0;
	struct dirent *de;
	char *systail;
	FILE *sysdev;
	unsigned long ma, mi;
	char *ep;
	ssize_t rd;

	dir = opendir(sysdir);
	if (!dir)
		return 0;

	*dirtailptr++ = '/';

	while (!done && (de = readdir(dir))) {
		/* Assume if we see a dot-name in sysfs it's special */
		if (de->d_name[0] == '.')
			continue;

		if (de->d_type != DT_UNKNOWN && de->d_type != DT_DIR)
			continue;

		if (strlen(de->d_name) >=
		    (BUF_SIZE - 64) - (dirtailptr - sysdir))
			continue;	/* Badness... */

		strcpy(dirtailptr, de->d_name);
		systail = strchr(sysdir, '\0');

		strcpy(systail, "/dev");
		sysdev = fopen(sysdir, "r");
		if (!sysdev)
			continue;

		/* Abusing the namebuf as temporary storage here. */
		rd = fread(namebuf, 1, BUF_SIZE, sysdev);
		namebuf[rd] = '\0';	/* Just in case... */

		fclose(sysdev);

		ma = strtoul(namebuf, &ep, 10);
		if (ma != major(dev) || *ep != ':')
			continue;

		mi = strtoul(ep + 1, &ep, 10);
		if (*ep != '\n')
			continue;

		if (mi == minor(dev)) {
			/* Found it! */
			strcpy(namebuf, de->d_name);
			done = 1;
		} else {
			/* we have a major number match, scan for partitions */
			*systail = '\0';
			done = scansysdir(namebuf, sysdir, dev);
		}
	}

	closedir(dir);
	return done;
}

const char *bdevname(dev_t dev)
{
	static char buf[BUF_SIZE];
	char sysdir[BUF_SIZE];
	char *p;

	strcpy(sysdir, "/sys/block");

	if (!scansysdir(buf, sysdir, dev))
		strcpy(buf, "dev");	/* prints e.g. dev(3,5) */

	p = strchr(buf, '\0');
	snprintf(p, sizeof buf - (p - buf), "(%d,%d)", major(dev), minor(dev));

	return buf;
}

#ifdef TEST_DEVNAME		/* Standalone test */

int main(int argc, char *argv[])
{
	dev_t dev;
	int i;

	for (i = 1; i < argc; i++) {
		dev = strtoul(argv[i], NULL, 0);

		printf("0x%08x = %s\n", (unsigned int)dev, bdevname(dev));
	}

	return 0;
}

#endif				/* TEST */
