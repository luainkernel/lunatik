#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>

int stat(const char *path, struct stat *buf)
{
	return fstatat(AT_FDCWD, path, buf, 0);
}
