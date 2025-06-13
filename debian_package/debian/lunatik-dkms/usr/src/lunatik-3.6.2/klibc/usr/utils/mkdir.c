#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "file_mode.h"

static mode_t leaf_mode, subdir_mode;
static int p_flag;

char *progname;

static __noreturn usage(void)
{
	fprintf(stderr, "Usage: %s [-p] [-m mode] dir...\n", progname);
	exit(1);
}

static int make_one_dir(char *dir, mode_t mode)
{
	struct stat stbuf;

	if (mkdir(dir, mode) == -1) {
		int err = errno;

		/*
		 * Ignore the error if it all of the following
		 * are satisfied:
		 *  - error was EEXIST
		 *  - -p was specified
		 *  - stat indicates that its a directory
		 */
		if (p_flag && errno == EEXIST &&
		    stat(dir, &stbuf) == 0 && S_ISDIR(stbuf.st_mode))
			return 1;
		errno = err;
		fprintf(stderr, "%s: ", progname);
		perror(dir);
		return -1;
	}
	return 0;
}

static int make_dir(char *dir)
{
	int ret;

	if (p_flag) {
		char *s, *p;

		/*
		 * Recurse each directory, trying to make it
		 * as we go.  Should we check to see if it
		 * exists, and if so if it's a directory
		 * before calling mkdir?
		 */
		s = dir;
		while ((p = strchr(s, '/')) != NULL) {
			/*
			 * Ignore the leading /
			 */
			if (p != dir) {
				*p = '\0';

				/*
				 * Make the intermediary directory.  POSIX
				 * says that these directories are created
				 * with umask,u+wx
				 */
				if (make_one_dir(dir, subdir_mode) == -1)
					return -1;

				*p = '/';
			}
			s = p + 1;
		}
	}

	/*
	 * Make the final target.  Only complain if the
	 * target already exists if -p was not specified.
	 * This is created with the asked for mode & ~umask
	 */
	ret = make_one_dir(dir, leaf_mode);
	if (ret == -1)
		return -1;

	/*
	 * We might not set all the permission bits.  Do that
	 * here (but only if we did create it.)
	 */
	if (ret == 0 && chmod(dir, leaf_mode) == -1) {
		int err_save = errno;

		/*
		 * We failed, remove the directory we created
		 */
		rmdir(dir);
		errno = err_save;
		fprintf(stderr, "%s: ", progname);
		perror(dir);
		return -1;
	}
	return 0;
}

int main(int argc, char *argv[])
{
	int c, ret = 0;
	mode_t saved_umask;

	progname = argv[0];

	saved_umask = umask(0);
	leaf_mode = (S_IRWXU | S_IRWXG | S_IRWXO) & ~saved_umask;
	subdir_mode = (saved_umask ^ (S_IRWXU | S_IRWXG | S_IRWXO))
	    | S_IWUSR | S_IXUSR;

	do {
		c = getopt(argc, argv, "pm:");
		if (c == EOF)
			break;
		switch (c) {
		case 'm':
			leaf_mode =
			    parse_file_mode(optarg, leaf_mode, saved_umask);
			break;
		case 'p':
			p_flag = 1;
			break;

		case '?':
			fprintf(stderr, "%s: invalid option -%c\n",
				progname, optopt);
			usage();
		}
	} while (1);

	if (optind == argc)
		usage();

	while (optind < argc) {
		if (make_dir(argv[optind]))
			ret = 255;	/* seems to be what gnu mkdir does */
		optind++;
	}

	return ret;
}
