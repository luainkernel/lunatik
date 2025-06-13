#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_access

int access(const char *pathname, int mode)
{
	return faccessat(AT_FDCWD, pathname, mode, 0);
}

#endif  /* __NR_access */
