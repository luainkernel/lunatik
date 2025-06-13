/*
 * fwrite2.c
 *
 * The actual fwrite() function as a non-inline
 */

#define __NO_STDIO_INLINES
#include <stdio.h>

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE * f)
{
	return _fwrite(ptr, size * nmemb, f) / size;
}
__ALIAS(size_t, fwrite_unlocked, (const void *, size_t, size_t, FILE *),
	fwrite)
