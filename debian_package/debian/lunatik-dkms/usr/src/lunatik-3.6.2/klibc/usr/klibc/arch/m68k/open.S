/*
 * arch/m68k/open.S
 *
 * Handle the open() system call - oddball due to the varadic
 * prototype, which forces the use of the cdecl calling convention,
 * and the need for O_LARGEFILE.
 */

#include <asm/unistd.h>

/* <asm/fcntl.h>, despite the name, isn't assembly-safe */
#define O_LARGEFILE	0400000

	.globl	open
	.type	open,@function

open:
	or.l	# O_LARGEFILE, 8(%sp)
	move.l	# __NR_open, %d0
	br	__syscall_common

	.size	open,.-open
