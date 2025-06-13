/*
 * usr/klibc/tests/vfork.c
 *
 * vfork is messy on most architectures.  Do our best to test it out.
 */

#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

int main(int argc, char *argv[])
{
	pid_t f, rv;
	int status;

	f = vfork();

	if (f == 0) {
		printf("Child (%d)...\n", (int)getpid());
		_exit(123);
	} else if (f > 0) {
		int err = 0;

		printf("Parent (child = %d)\n", (int)f);

		rv = waitpid(f, &status, 0);
		if (rv != f) {
			printf("waitpid returned %d, errno = %d\n",
			       (int)rv, errno);
			err++;
		}
		if (!WIFEXITED(status) || WEXITSTATUS(status) != 123) {
			printf("Child process existed with wrong status %d\n",
			       status);
			err++;
		}
		return err;
	} else {
		printf("vfork returned %d, errno = %d\n",
		       (int)f, errno);
		return 127;
	}
}
