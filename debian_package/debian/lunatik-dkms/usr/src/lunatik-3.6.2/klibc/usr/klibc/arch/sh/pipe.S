/*
 * arch/sh/pipe.S
 *
 * The pipe system call is special on sh: it returns
 * the two file descriptors in r0 and r1.
 */

#include <asm/unistd.h>

	.section ".text.syscall","ax"
	.align	2
	.globl	pipe
	.type	pipe,@function
pipe:
	mov	#__NR_pipe, r3
	trapa	#0x10
	mov.l	1f,r2
	cmp/hs	r0,r2
	bt/s	3f
	  neg	r0,r2
	mov.l	2f,r3
	mov.l	r2,@r3
	rts
	  mov	#-1,r0
3:
	mov.l   r0, @r4
	mov.l   r1, @(4, r4)
	rts
	  mov	#0,r0

	.align 2
1:	.long	-4096		/* Errno limit */
2:	.long	errno

	.size	pipe,.-pipe
