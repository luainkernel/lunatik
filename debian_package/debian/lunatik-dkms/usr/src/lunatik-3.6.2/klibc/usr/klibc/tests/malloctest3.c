#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	void *p;

	/* Our implementation should always return NULL */
	errno = 0;
	p = malloc(0);
	assert(p == NULL);
	assert(errno == 0);

	/* These sizes won't fit in memory, so should always fail */
	errno = 0;
	p = malloc(SIZE_MAX);
	assert(p == NULL);
	assert(errno == ENOMEM);
	errno = 0;
	p = malloc(SIZE_MAX - 0x10000);
	assert(p == NULL);
	assert(errno == ENOMEM);

#if SIZE_MAX > 0x100000000
	/* We should be able to allocate 4 GB + 1 */
	p = malloc(0x100000001);
	assert(p != NULL);
	((volatile char *)p)[0x100000000] = 1;
	free(p);

	/* calloc() should detect multiplication overflow */
	errno = 0;
	p = calloc(0x100000000, 0x100000000);
	assert(p == NULL);
	assert(errno == ENOMEM);
	errno = 0;
	p = calloc(0x100000001, 0x100000001);
	assert(p == NULL);
	assert(errno == ENOMEM);
#else
	/* calloc() should detect multiplication overflow */
	errno = 0;
	p = calloc(0x10000, 0x10000);
	assert(p == NULL);
	assert(errno == ENOMEM);
	errno = 0;
	p = calloc(0x10001, 0x10001);
	assert(p == NULL);
	assert(errno == ENOMEM);
#endif

	return 0;
}
