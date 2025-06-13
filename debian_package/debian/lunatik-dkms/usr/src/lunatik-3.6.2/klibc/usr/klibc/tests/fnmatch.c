#include <stdio.h>
#include <stdlib.h>
#include <fnmatch.h>

int main(int argc, char *argv[])
{
	int flags = atoi(argv[3]);
	int match = fnmatch(argv[1], argv[2], flags);

	printf("\"%s\" matches \"%s\": %d\n", argv[1], argv[2], match);

	return match;
}
