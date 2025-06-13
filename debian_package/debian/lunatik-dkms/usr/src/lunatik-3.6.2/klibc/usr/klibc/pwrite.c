/*
 * pwrite.c
 *
 * Some architectures need to wrap the system call
 */

#include <sys/types.h>
#include <endian.h>
#include <sys/syscall.h>

#if defined(__hppa__)

#if _BITSIZE == 32
extern ssize_t __pwrite(int, const void *, size_t, unsigned int, unsigned int);
#else
extern ssize_t __pwrite(int, const void *, size_t, off_t);
#endif

size_t pwrite(int fd, void *buf, size_t count, off_t offset)
{
#if _BITSIZE == 32
	unsigned int hi = offset >> 32;
	unsigned int lo = (unsigned int) offset;
	return __pwrite(fd, buf, count, __LONG_LONG_PAIR(hi, lo));
#else
	return __pwrite(fd, buf, count, offset);
#endif
}

#endif
