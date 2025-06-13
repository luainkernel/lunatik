#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <errno.h>

int main(int argc, char *argv[])
{
	struct timespec ts;
	char *p;

	if (argc != 2)
		goto err;

	p = strtotimespec(argv[1], &ts);
	if (*p)
		goto err;

	while (nanosleep(&ts, &ts) == -1 && errno == EINTR)
		;

	return 0;

err:
	fprintf(stderr, "Usage: %s seconds[.fraction]\n", argv[0]);
	return 1;
}
