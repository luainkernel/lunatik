#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>

int main(void)
{
	/* Size of message must be <= PIPE_BUF */
	const char msg[] = "Hello, World!";
	char buf[512];
	int rv;
	int pfd[2];

	if (pipe(pfd)) {
		perror("pipe");
		return 1;
	}

	if (write(pfd[1], msg, sizeof msg) != sizeof msg) {
		perror("write");
		return 1;
	}

	while ((rv = read(pfd[0], buf, sizeof buf)) < sizeof msg) {
		if (rv == -1 && errno == EINTR)
			continue;
		perror("read");
		return 1;
	}

	if (memcmp(msg, buf, sizeof msg)) {
		fprintf(stderr, "Message miscompare!\n");
		return 1;
	}

	return 0;
}
