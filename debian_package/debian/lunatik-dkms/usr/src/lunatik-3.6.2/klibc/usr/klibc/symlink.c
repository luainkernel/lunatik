#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_symlink

int symlink(const char *oldpath, const char *newpath)
{
	return symlinkat(oldpath, AT_FDCWD, newpath);
}

#endif /* __NR_symlink */
