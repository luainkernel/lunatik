/*
 * getoptlong.c
 *
 * Simple test for getopt_long, set the environment variable GETOPTTEST
 * to give the argument string to getopt()
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <getopt.h>

static int foo = 0;

static const struct option long_options[] = {
	{ "first",   1, NULL, 'f' },
	{ "second",  0, NULL, 's' },
	{ "third",   2, NULL, '3' },
	{ "fourth",  0, NULL,  4 },
	{ "set-foo", 0, &foo,  1 },
	{ NULL, 0, NULL, 0 }
};

int main(int argc, char *const *argv)
{
	const char *parser;
	const char *showchar;
	char one_char[] = "\'?\'";
	char num_buf[16];
	int c;
	int longindex;

	parser = getenv("GETOPTTEST");
	if (!parser)
		parser = "abzf:o:";

	do {
		c = getopt_long(argc, argv, parser, long_options, &longindex);

		if (c == EOF) {
			showchar = "EOF";
		} else if (c >= 32 && c <= 126) {
			one_char[1] = c;
			showchar = one_char;
		} else {
			snprintf(num_buf, sizeof num_buf, "%d", c);
			showchar = num_buf;
		}

		printf("c = %s, optind = %d (\"%s\"), optarg = \"%s\", "
		       "optopt = \'%c\', foo = %d, longindex = %d\n",
		       showchar, optind, argv[optind],
		       optarg, optopt, foo, longindex);
	} while (c != -1);

	return 0;
}
