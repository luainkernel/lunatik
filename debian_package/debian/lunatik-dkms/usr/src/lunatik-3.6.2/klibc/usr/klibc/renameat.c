#include <fcntl.h>
#include <stdio.h>

#ifndef __NR_renameat

int renameat(int olddirfd, const char *oldpath,
	     int newdirfd, const char *newpath)
{
	return renameat2(olddirfd, oldpath, newdirfd, newpath, 0);
}

#endif /* __NR_renameat */
