/*
 * Open a file and read it, assuming it contains a single long value.
 * Return 0 if we read a valid value, otherwise -1.
 */

#include <stdio.h>
#include <stdlib.h>

#include "kinit.h"

int getintfile(const char *path, long *val)
{
	char buffer[64];
	char *ep;
	FILE *f;

	f = fopen(path, "r");
	if (!f)
		return -1;

	ep = buffer + fread(buffer, 1, sizeof buffer - 1, f);
	fclose(f);
	*ep = '\0';

	*val = strtol(buffer, &ep, 0);
	if (*ep && *ep != '\n')
		return -1;
	else
		return 0;
}
