#include <assert.h>
#include <stdio.h>
#include <sys/sysconf.h>

int main(void)
{
	long rc;

	rc = sysconf(_SC_PAGESIZE);
	assert(rc > 0);
	printf("sysconf(_SC_PAGESIZE) = %ld\n", rc);

	return 0;
}
