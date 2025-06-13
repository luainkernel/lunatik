#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>

int fstat(int fd, struct stat *buf)
{
	return fstatat(fd, "", buf, AT_EMPTY_PATH);
}
