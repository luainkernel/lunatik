#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>

char *progname;

static __noreturn usage(void)
{
	fprintf(stderr, "Usage: %s pid\n", progname);
	exit(1);
}
int main(int argc, char *argv[])
{
	long pid;
	char *endp;

	progname = argv[0];
	if (argc != 2)
		usage();

	pid = strtol(argv[1], &endp, 10);
	if (*endp != '\0') {
		perror("pid");
		usage();
	}

	if (kill(pid, SIGTERM) == -1) {
		perror("kill");
		exit(-1);
	}
	exit(0);
}
