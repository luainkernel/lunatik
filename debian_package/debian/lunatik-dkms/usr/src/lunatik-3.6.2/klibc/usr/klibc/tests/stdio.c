#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <arpa/inet.h>
#include <inttypes.h>

#define TEST_WORDS (1024*1024)

int main(void)
{
	FILE *f;
	int i, n;
	uint32_t *buf1, *buf2, *p;

	printf("Hello, World!\nHello again");
	printf(" - and some more - ");
	printf("and some more\n");

	buf1 = mmap(NULL, 2*4*TEST_WORDS, PROT_READ|PROT_WRITE,
		   MAP_ANONYMOUS|MAP_PRIVATE, 0, 0);
	if (buf1 == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	buf2 = buf1 + TEST_WORDS;

	p = buf1;
	for (i = 0; i < TEST_WORDS; i++)
		*p++ = htonl(i);

	f = fopen("test.out", "w+b");
	if (!f) {
		perror("fopen");
		return 1;
	}

	for (i = 2; i < TEST_WORDS; i += (i >> 1)) {
		n = fwrite(buf1, 4, i, f);
		if (n != i) {
			perror("fwrite");
			return 1;
		}
	}

	fprintf(f, "Writing to the file...\n");
	fprintf(f, "Writing to the file ");
	fprintf(f, "some more\n");

	fseek(f, 0, SEEK_SET);

	for (i = 2; i < TEST_WORDS; i += (i >> 1)) {
		n = fread(buf2, 4, i, f);
		if (n != i) {
			perror("fread");
			return 1;
		}

		if (memcmp(buf1, buf2, i*4)) {
			fprintf(stderr, "memory mismatch error, i = %d\n", i);
			return 1;
		}
	}

	fclose(f);
	return 0;
}
