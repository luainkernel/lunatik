/*
 * arch/sparc/pipe.S
 *
 * The pipe system call are special on sparc[64]:
 * they return the two file descriptors in %o0 and %o1.
 */

#include <machine/asm.h>
#include <asm/unistd.h>

	.globl	pipe
	.type	pipe,#function
       	.align	4
pipe:
	mov	__NR_pipe, %g1
	or	%o0, 0, %g4
	t	0x10
	bcc	1f
	  nop
	PIC_PROLOGUE(%g1,%g4)
	SET(errno,%g1,%g4)
	st	%o0,[%g4]
	retl
	  mov	-1, %o0
1:
	st	%o0,[%g4]
	st	%o1,[%g4+4]
	retl
	  mov	0, %o0

	.size pipe,.-pipe
