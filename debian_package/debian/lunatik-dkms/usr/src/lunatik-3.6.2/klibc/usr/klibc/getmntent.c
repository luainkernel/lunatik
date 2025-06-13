#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mntent.h>

#define BUFLEN 1024

struct mntent *getmntent_r(FILE *fp, struct mntent *mntbuf, char *buf,
		int buflen)
{
	char *line = NULL, *saveptr = NULL;
	const char *sep = " \t\n";

	if (!fp || !mntbuf || !buf)
		return NULL;

	while ((line = fgets(buf, buflen, fp)) != NULL) {
		if (buf[0] == '#' || buf[0] == '\n')
			continue;
		break;
	}

	if (!line)
		return NULL;

	mntbuf->mnt_fsname = strtok_r(buf, sep, &saveptr);
	if (!mntbuf->mnt_fsname)
		return NULL;

	mntbuf->mnt_dir = strtok_r(NULL, sep, &saveptr);
	if (!mntbuf->mnt_fsname)
		return NULL;

	mntbuf->mnt_type = strtok_r(NULL, sep, &saveptr);
	if (!mntbuf->mnt_type)
		return NULL;

	mntbuf->mnt_opts = strtok_r(NULL, sep, &saveptr);
	if (!mntbuf->mnt_opts)
		mntbuf->mnt_opts = "";

	line = strtok_r(NULL, sep, &saveptr);
	mntbuf->mnt_freq = !line ? 0 : atoi(line);

	line = strtok_r(NULL, sep, &saveptr);
	mntbuf->mnt_passno = !line ? 0 : atoi(line);

	return mntbuf;
}

struct mntent *getmntent(FILE *fp)
{
	static char *buf = NULL;
	static struct mntent mntbuf;

	buf = malloc(BUFLEN);
	if (!buf)
		perror("malloc");

	return getmntent_r(fp, &mntbuf, buf, BUFLEN);
}
