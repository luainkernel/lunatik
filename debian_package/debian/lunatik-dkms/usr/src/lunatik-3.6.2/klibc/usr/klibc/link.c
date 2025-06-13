#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_link

int link(const char *oldpath, const char *newpath)
{
	return linkat(AT_FDCWD, oldpath, AT_FDCWD, newpath, 0);
}

#endif  /* __NR_link */
