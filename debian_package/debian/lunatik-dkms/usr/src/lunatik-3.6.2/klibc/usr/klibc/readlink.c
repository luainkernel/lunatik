#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_readlink

int readlink(const char *path, char *buf, size_t bufsiz)
{
	return readlinkat(AT_FDCWD, path, buf, bufsiz);
}

#endif /* __NR_readlink */
