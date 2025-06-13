#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_mknod

int mknod(const char *pathname, mode_t mode, dev_t dev)
{
	return mknodat(AT_FDCWD, pathname, mode, dev);
}

#endif  /* __NR_mknod  */
