/*
 * calloc.c
 */

#include <errno.h>
#include <stdlib.h>
#include <string.h>

void *calloc(size_t nmemb, size_t size)
{
	unsigned long prod;

	if (__builtin_umull_overflow(nmemb, size, &prod)) {
		errno = ENOMEM;
		return NULL;
	}
	return zalloc(prod);
}
