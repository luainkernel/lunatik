#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

char *progname;

static __noreturn usage(void)
{
	fprintf(stderr, "Usage: %s [-m mode] name {b|c|p} major minor\n",
			progname);
	exit(1);
}

int main(int argc, char *argv[])
{
	char *name, *type, typec, *endp;
	unsigned int major_num, minor_num;
	mode_t mode, mode_set = 0;
	dev_t dev;

	progname = *argv++;
	if (argc == 1)
		usage();

	if (argv[0][0] == '-' && argv[0][1] == 'm' && !argv[0][2]) {
		mode_set = strtoul(argv[1], &endp, 8);
		argv += 2;
	}

	name = *argv++;
	if (!name)
		usage();

	type = *argv++;
	if (!type || !type[0] || type[1])
		usage();
	typec = type[0];

	mode = 0;
	switch (typec) {
	case 'c':
		mode = S_IFCHR;
		break;
	case 'b':
		mode = S_IFBLK;
		break;
	case 'p':
		mode = S_IFIFO;
		break;
	default:
		usage();
	}

	if (mode == S_IFIFO) {
		dev = 0;
	} else {
		if (!argv[0] || !argv[1])
			usage();

		major_num = strtol(*argv++, &endp, 0);
		if (*endp != '\0')
			usage();
		minor_num = strtol(*argv++, &endp, 0);
		if (*endp != '\0')
			usage();
		dev = makedev(major_num, minor_num);
	}

	if (*argv)
		usage();

	if (mknod(name, mode|0666, dev) == -1) {
		perror("mknod");
		exit(1);
	}

	if (mode_set && chmod(name, mode_set)) {
		perror("chmod");
		exit(1);
	}

	exit(0);
}
