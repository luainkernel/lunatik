#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>

const char *progname;

static __noreturn usage(void)
{
	fprintf(stderr, "Usage: %s [-f] link...\n", progname);
	exit(1);
}

int main(int argc, char *argv[])
{
	int c, f_flag = 0;
	const char *name;
	char link_name[PATH_MAX];
	int rv;

	progname = argv[0];

	do {
		c = getopt(argc, argv, "f");
		if (c == EOF)
			break;
		switch (c) {
		case 'f':
			f_flag = 1;
			break;

		case '?':
			fprintf(stderr, "%s: invalid option -%c\n",
				progname, optopt);
			usage();
		}
	} while (1);

	if (optind == argc)
		usage();

	argv += optind;
	while ((name = *argv++)) {
		if (f_flag)
			rv = realpath(name, link_name) ? strlen(link_name) : -1;
		else
			rv = readlink(name, link_name, sizeof link_name - 1);
		if (rv < 0) {
			perror(name);
			exit(1);
		}
		link_name[rv] = '\n';
		_fwrite(link_name, rv+1, stdout);
	}

	return 0;
}
