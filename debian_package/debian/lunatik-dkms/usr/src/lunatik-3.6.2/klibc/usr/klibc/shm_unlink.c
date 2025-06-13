/*
 * shm_unlink.c
 *
 * POSIX shared memory support
 */

#include <stdlib.h>
#include <alloca.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>


int shm_unlink(const char *path)
{
	int len = strlen(path);
	char *pathbuf = alloca(len+10);

	memcpy(pathbuf, "/dev/shm/", 9);
	memcpy(pathbuf+9, path, len+1);

	return unlink(path);
}
