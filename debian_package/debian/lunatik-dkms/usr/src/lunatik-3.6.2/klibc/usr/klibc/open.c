/*
 * open.c
 *
 * On 32-bit platforms we need to pass O_LARGEFILE to the open()
 * system call, to indicate that we're 64-bit safe.
 *
 * For 64 bit systems without the open syscall, pass straight
 * through into openat.
 */

#define _KLIBC_IN_OPEN_C
#include <unistd.h>
#include <fcntl.h>
#include <bitsize.h>
#include <sys/syscall.h>

#ifndef __NR_open
#if _BITSIZE == 32

extern int __openat(int, const char *, int, mode_t);

int open(const char *pathname, int flags, mode_t mode)
{
	return __openat(AT_FDCWD, pathname, flags | O_LARGEFILE, mode);
}

#else

__extern int openat(int, const char *, int, ...);

int open(const char *pathname, int flags, mode_t mode)
{
	return openat(AT_FDCWD, pathname, flags, mode);
}

#endif /* _BITSIZE == 32 */

#elif _BITSIZE == 32 && !defined(__i386__) && !defined(__m68k__)

extern int __open(const char *, int, mode_t);

int open(const char *pathname, int flags, mode_t mode)
{
	return __open(pathname, flags | O_LARGEFILE, mode);
}

#endif /* __NR_open */
