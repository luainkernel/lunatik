#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <linux/limits.h>

int main(int argc, char *argv[])
{
	int c, s, f;
	char *p;
	struct stat sb;

	s = f = 0;
	do {
		c = getopt(argc, argv, "sf");
		if (c == EOF)
			break;

		switch (c) {

		case 's':
			s = 1;
			break;
		case 'f':
			f = 1;
			break;
		case '?':
			fprintf(stderr, "%s: invalid option -%c\n",
				argv[0], optopt);
			return 1;
		}

	} while (1);

	if (optind == argc) {
		fprintf(stderr, "Usage: %s [-s] [-f] target link\n", argv[0]);
		return 1;
	}

	memset(&sb, 0, sizeof(struct stat));
	if (stat(argv[argc - 1], &sb) < 0 && argc - optind > 2) {
		if (!(S_ISDIR(sb.st_mode))) {
			fprintf(stderr,
				"multiple targets and %s is not a directory\n",
				argv[argc - 1]);
			return 1;
		}
	}

	for (c = optind; c < argc - 1; c++) {
		char target[PATH_MAX];

		p = strrchr(argv[c], '/');
		p++;

		if (S_ISDIR(sb.st_mode))
			snprintf(target, PATH_MAX, "%s/%s", argv[argc - 1], p);
		else
			snprintf(target, PATH_MAX, "%s", argv[argc - 1]);

		if (f)
			unlink(target);

		if (s) {
			if (symlink(argv[c], target) == -1)
				perror(target);
		} else {
			if (link(argv[c], target) == -1)
				perror(target);
		}
	}

	return 0;
}
