/*
 * fread2.c
 *
 * The actual fread() function as a non-inline
 */

#define __NO_STDIO_INLINES
#include <stdio.h>

size_t fread(void *ptr, size_t size, size_t nmemb, FILE * f)
{
	return _fread(ptr, size * nmemb, f) / size;
}
__ALIAS(size_t, fread_unlocked, (void *, size_t, size_t, FILE *), fread)
