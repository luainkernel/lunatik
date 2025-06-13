/*
 * arch/alpha/sigreturn.S
 */

#include <machine/asm.h>
#include <asm/unistd.h>

	.text
	.align	3
	.type	__sigreturn,@function
	.ent	__sigreturn,0
	.globl	__sigreturn
__sigreturn:
	mov	sp,a0			# struct sigcontext on stack
	lda	v0,__NR_rt_sigreturn(zero)
	callsys
	.size	__sigreturn,.-__sigreturn
	.end	__sigreturn
