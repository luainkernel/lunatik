/*
 * lseek.c
 *
 * On 32-bit platforms, we need to use the _llseek() system call
 * rather than lseek(), to be able to handle large disks.  _llseek()
 * isn't just a normal syscall which takes a 64-bit argument; it needs
 * to return a 64-bit value and so takes an extra pointer.
 */

#include <unistd.h>
#include <sys/syscall.h>
#include <bitsize.h>

#if _BITSIZE == 32

extern int __llseek(int fd, unsigned long hi, unsigned long lo, off_t * res,
		    int whence);

off_t lseek(int fd, off_t offset, int whence)
{
	unsigned long long ullo = offset;
	off_t result;
	int rv;

	rv = __llseek(fd, (unsigned long)(ullo >> 32), (unsigned long)ullo,
		      &result, whence);

	return rv ? (off_t)-1 : result;
}

#endif
