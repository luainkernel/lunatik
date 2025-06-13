/*
 * mmap.c
 */

#include <stdint.h>
#include <errno.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <unistd.h>
#include <bitsize.h>
#include <klibc/sysconfig.h>

/*
 * Set in SYSCALLS whether or not we should use an unadorned mmap() system
 * call (typical on 64-bit architectures).
 */
#if _KLIBC_USE_MMAP2

/* This architecture uses mmap2(). The Linux mmap2() system call takes
   a page offset as the offset argument.  We need to make sure we have
   the proper conversion in place. */

extern void *__mmap2(void *, size_t, int, int, int, size_t);

void *mmap(void *start, size_t length, int prot, int flags, int fd,
	   off_t offset)
{
	const int mmap2_shift = _KLIBC_MMAP2_SHIFT;
	const off_t mmap2_mask = ((off_t) 1 << mmap2_shift) - 1;

	if (offset & mmap2_mask) {
		errno = EINVAL;
		return MAP_FAILED;
	}

	return __mmap2(start, length, prot, flags, fd,
		       (size_t) offset >> mmap2_shift);
}

#endif
