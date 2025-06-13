/*
 * asprintf.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

int asprintf(char **bufp, const char *format, ...)
{
	va_list ap;
	int rv;

	va_start(ap, format);
	rv = vasprintf(bufp, format, ap);
	va_end(ap);

	return rv;
}
