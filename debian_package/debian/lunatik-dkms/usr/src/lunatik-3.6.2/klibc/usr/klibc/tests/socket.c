#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>

int main(int argc, char *argv[])
{
	int ret;

	ret = socket(AF_INET, SOCK_DGRAM, 0);
	if (ret == -1) {
		fprintf(stderr, "klibc: socket(AF_INET): %s\n",
				strerror(errno));
		return 1;
	}

	return 0;
}
