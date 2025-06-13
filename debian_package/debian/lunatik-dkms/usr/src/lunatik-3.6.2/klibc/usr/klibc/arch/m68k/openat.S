/*
 * arch/m68k/openat.S
 *
 * Handle the openat() system call - oddball due to the varadic
 * prototype, which forces the use of the cdecl calling convention,
 * and the need for O_LARGEFILE.
 */

#include <asm/unistd.h>

/* <asm/fcntl.h>, despite the name, isn't assembly-safe */
#define O_LARGEFILE	0400000

#ifdef __NR_openat		/* Don't build if kernel headers too old */

	.globl	openat
	.type	openat,@function

openat:
	or.l	# O_LARGEFILE, 12(%sp)
	move.l	# __NR_openat, %d0
	br	__syscall_common

	.size	openat,.-openat

#endif
