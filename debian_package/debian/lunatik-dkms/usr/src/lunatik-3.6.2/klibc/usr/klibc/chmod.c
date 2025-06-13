#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>

#ifndef __NR_chmod

int chmod(const char *path, mode_t mode)
{
	return fchmodat(AT_FDCWD, path, mode, 0);
}

#endif  /* __NR_chmod */
