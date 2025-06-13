#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_chown

int chown(const char *path, uid_t owner, gid_t group)
{
	return fchownat(AT_FDCWD, path, owner, group, 0);
}

#endif  /* __NR_chown  */
