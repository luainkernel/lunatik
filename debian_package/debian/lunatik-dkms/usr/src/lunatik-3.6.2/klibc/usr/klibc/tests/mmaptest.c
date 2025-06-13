/*
 * mmaptest.c
 *
 * Test some simple cases of mmap()
 */

#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <fcntl.h>

static void make_test_file(int fd)
{
	unsigned long v;
	FILE *f = fdopen(fd, "wb");

	for (v = 0; v < 262144; v += sizeof(v))
		_fwrite(&v, sizeof(v), f);
}

int main(int argc, char *argv[])
{
	void *foo;
	char *test_file = (argc > 1) ? argv[1] : "/tmp/mmaptest.tmp";
	int rv, fd;

	/* Important case, this is how we get memory for malloc() */
	errno = 0;
	foo = mmap(NULL, 65536, PROT_READ | PROT_WRITE,
		   MAP_PRIVATE | MAP_ANONYMOUS, 0, 0);

	printf("mmap() returned %p, errno = %d\n", foo, errno);
	if (foo == MAP_FAILED)
		return 1;

	rv = munmap(foo, 65536);
	printf("munmap() returned %d, errno = %d\n", rv, errno);
	if (rv)
		return 1;

	/* Create test file */
	fd = open(test_file, O_RDWR | O_CREAT | O_TRUNC, 0666);
	if (fd < 0) {
		perror(test_file);
		return 1;
	}

	make_test_file(fd);

	/* Map test file */
	foo = mmap(NULL, 65536, PROT_READ, MAP_SHARED, fd, 131072);
	printf("mmap() returned %p, errno = %d\n", foo, errno);
	if (foo == MAP_FAILED)
		return 1;

	if (*(unsigned long *)foo != 131072) {
		printf("mmap() with offset returned the wrong offset %ld!\n",
		       *(unsigned long *)foo);
		return 1;
	}

	if (munmap(foo, 65536)) {
		printf("munmap() returned nonzero, errno = %d\n", errno);
		return 1;
	}

	close(fd);
	unlink(test_file);

	return 0;
}
