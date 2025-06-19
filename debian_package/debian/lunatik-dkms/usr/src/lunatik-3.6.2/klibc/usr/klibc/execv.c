/*
 * execv.c
 */

#include <unistd.h>

int execv(const char *path, char *const *argv)
{
	return execve(path, argv, environ);
}
