#include <unistd.h>
#include <stdio.h>
#include <ctype.h>
#include <stdlib.h>
#include <sys/klog.h>

static void usage(char *name)
{
	fprintf(stderr, "usage: %s [-c]\n", name);
}

int main(int argc, char *argv[])
{
	char *buf = NULL;
	const char *p;
	int c;
	int bufsz = 0;
	int cmd = 3;	/* Read all messages remaining in the ring buffer */
	int len = 0;
	int opt;
	int newline;

	while ((opt = getopt(argc, argv, "c")) != -1) {
		switch (opt) {
		/* Read and clear all messages remaining in the ring buffer */
		case 'c':
			cmd = 4;
			break;
		case '?':
		default:
			usage(argv[0]);
			exit(1);
		}
	}

	if (!bufsz) {
		len = klogctl(10, NULL, 0); /* Get size of log buffer */
		if (len > 0)
			bufsz = len;
	}

	if (bufsz) {
		int sz = bufsz + 8;

		buf = (char *)malloc(sz);
		len = klogctl(cmd, buf, sz);
	}

	if (len < 0) {
		perror("klogctl");
		exit(1);
	}

	newline = 1;
	p = buf;
	while ((c = *p)) {
		switch (c) {
		case '\n':
			newline = 1;
			putchar(c);
			p++;
			break;
		case '<':
			if (newline && isdigit(p[1]) && p[2] == '>') {
				p += 3;
				break;
			}
			/* else fall through */
		default:
			newline = 0;
			putchar(c);
			p++;
		}
	}
	if (!newline)
		putchar('\n');

	return 0;
}
