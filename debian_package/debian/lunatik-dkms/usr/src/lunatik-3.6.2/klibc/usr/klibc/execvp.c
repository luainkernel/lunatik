/*
 * execvp.c
 */

#include <unistd.h>

int execvp(const char *path, char *const *argv)
{
	return execvpe(path, argv, environ);
}
