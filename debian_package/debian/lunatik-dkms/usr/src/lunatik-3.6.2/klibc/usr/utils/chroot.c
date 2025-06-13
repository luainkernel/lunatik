/*
 * by rmk
 */
#include <unistd.h>
#include <stdio.h>

int main(int argc, char *argv[], char *envp[])
{
	if (argc < 3) {
		fprintf(stderr, "Usage: %s newroot command...\n", argv[0]);
		return 1;
	}

	if (chroot(argv[1]) == -1) {
		perror("chroot");
		return 1;
	}

	if (chdir("/") == -1) {
		perror("chdir");
		return 1;
	}

	if (execvp(argv[2], argv + 2) == -1) {
		perror("execvp");
		return 1;
	}

	return 0;
}
