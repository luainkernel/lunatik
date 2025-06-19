/*
 * arch/sparc/syscall.S
 *
 * Common system-call stub; %g1 already set to syscall number
 */

#include <machine/asm.h>

	.globl	__syscall_common
	.type	__syscall_common,#function
       	.align	4
__syscall_common:
	t	0x10
	bcc	1f
	  PIC_PROLOGUE(%g1,%g4)
	SET(errno,%g1,%g4)
	st	%o0,[%g4]
	mov	-1, %o0
1:
       	retl
	  nop
