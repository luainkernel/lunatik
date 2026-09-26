/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace peer for the device returns test (see returns.sh): reads and writes
* <device> through a buffer at an unmapped address and prints what each call
* answered, "read: <error>" and "write: <error>", or the count it moved.
*/

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

static void report(const char *op, ssize_t ret, int error)
{
	if (ret < 0)
		printf("%s: %s\n", op, strerror(error));
	else
		printf("%s: %zd\n", op, ret);
}

/* a page mapped and given back, whose address nothing maps again before the calls */
static void *unmapped(void)
{
	long page = sysconf(_SC_PAGESIZE);
	int zero = open("/dev/zero", O_RDONLY);
	void *addr;

	if (zero < 0)
		return MAP_FAILED;
	addr = mmap(NULL, page, PROT_READ, MAP_PRIVATE, zero, 0);
	close(zero);
	if (addr != MAP_FAILED && munmap(addr, page) < 0)
		return MAP_FAILED;
	return addr;
}

int main(int argc, char *argv[])
{
	void *buf;
	ssize_t rret, wret;
	int fd, rerr, werr;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <device>\n", argv[0]);
		return 2;
	}
	if ((buf = unmapped()) == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	if ((fd = open(argv[1], O_RDWR)) < 0) {
		perror(argv[1]);
		return 1;
	}

	rret = read(fd, buf, 1);
	rerr = errno;
	wret = write(fd, buf, 1);
	werr = errno;
	close(fd);

	report("read", rret, rerr);
	report("write", wret, werr);
	return 0;
}

