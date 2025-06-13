#
# arch/alpha/pipe.S
#

#
# pipe() on alpha returns both file descriptors in registers --
# $0 (v0) and $20 (a4) respectively.  This is unlike any other system call,
# as far as I can tell.
#

#include <asm/unistd.h>
#include <machine/asm.h>

	.text
	.align	3
	.type	pipe, @function
	.ent	pipe, 0
	.globl	pipe
pipe:
	.frame	sp,0,ra,0
	lda	v0, __NR_pipe
	callsys
	beq	a3, 1f
	br	pv, 2f			# pv <- pc
2:
	ldgp	gp, 0(pv)
	lda	a1, errno
	lda	v0, -1(zero)
	stl	a3, 0(a1)
	ret	zero,(ra),1
1:
	stl	v0, 0(a0)
	lda	v0, 0
	stl	a4, 4(a0)
	ret	zero,(ra),1

	.size	pipe,.-pipe
	.end	pipe
