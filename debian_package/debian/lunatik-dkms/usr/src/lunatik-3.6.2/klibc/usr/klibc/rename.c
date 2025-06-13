#include <fcntl.h>
#include <stdio.h>

#ifndef __NR_rename

int rename(const char *oldpath, const char *newpath)
{
	return renameat2(AT_FDCWD, oldpath, AT_FDCWD, newpath, 0);
}

#endif /* __NR_rename */
