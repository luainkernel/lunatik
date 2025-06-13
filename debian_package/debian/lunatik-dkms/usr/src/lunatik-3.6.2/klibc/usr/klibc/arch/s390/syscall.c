/*
 * arch/s390/syscall.c
 *
 * Common error-handling path for system calls.
 * The return value from __syscall_common becomes the
 * return value from the system call.
 */
#include <errno.h>

unsigned long __syscall_common(unsigned long err)
{
	if (err < -4095UL)
		return err;
	errno = -err;
	return -1;
}
