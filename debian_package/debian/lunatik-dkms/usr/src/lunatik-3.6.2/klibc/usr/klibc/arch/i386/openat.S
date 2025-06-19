/*
 * arch/i386/openat.S
 *
 * Handle the openat() system call - oddball due to the varadic
 * prototype, which forces the use of the cdecl calling convention,
 * and the need for O_LARGEFILE.
 */

#include <asm/unistd.h>

/* <asm/fcntl.h>, despite the name, isn't assembly-safe */
#define O_LARGEFILE     0100000

#ifdef __NR_openat		/* Don't build if kernel headers too old */

	.globl	openat
	.type	openat,@function

openat:
	orl	$O_LARGEFILE,12(%esp)
	pushl	$__NR_openat
	jmp	__syscall_varadic

	.size	openat,.-openat

#endif
