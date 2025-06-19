#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "file_mode.h"

static mode_t leaf_mode;

char *progname;

static int make_fifo(char *dir)
{
	if (mkfifo(dir, leaf_mode)) {
		/*
		 * We failed, remove the directory we created.
		 */
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
	leaf_mode =
	    (S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH) &
	    ~saved_umask;

	do {
		c = getopt(argc, argv, "m:");
		if (c == EOF)
			break;
		switch (c) {
		case 'm':
			leaf_mode =
			    parse_file_mode(optarg, leaf_mode, saved_umask);
			break;

		case '?':
			fprintf(stderr, "%s: invalid option -%c\n",
				progname, optopt);
			exit(1);
		}
	} while (1);

	if (optind == argc) {
		fprintf(stderr, "Usage: %s [-m mode] file...\n", progname);
		exit(1);
	}

	while (optind < argc) {
		if (make_fifo(argv[optind]))
			ret = 255;	/* seems to be what gnu mkdir does */
		optind++;
	}

	return ret;
}
