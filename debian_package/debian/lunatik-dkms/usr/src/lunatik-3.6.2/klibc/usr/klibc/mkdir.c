#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_mkdir

int mkdir(const char *pathname, mode_t mode)
{
	return mkdirat(AT_FDCWD, pathname, mode);
}

#endif /* __NR_mkdir */
