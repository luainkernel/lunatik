#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_dup2

int dup2(int fd, int fd2)
{
	return dup3(fd, fd2, 0);
}

#endif /* __NR_dup2 */
