#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_unlink

int unlink(const char *pathname)
{
	return unlinkat(AT_FDCWD, pathname, 0);
}

#endif  /* __NR_unlink */
