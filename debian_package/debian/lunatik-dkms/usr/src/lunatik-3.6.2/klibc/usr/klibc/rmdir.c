#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_rmdir

int rmdir(const char *pathname)
{
	return unlinkat(AT_FDCWD, pathname, AT_REMOVEDIR);
}

#endif /* __NR_rmdir */
