/*
 * zalloc.c
 */

#include <stdlib.h>
#include <string.h>

void *zalloc(size_t size)
{
	void *ptr;

	ptr = malloc(size);
	if (ptr)
		memset(ptr, 0, size);

	return ptr;
}
