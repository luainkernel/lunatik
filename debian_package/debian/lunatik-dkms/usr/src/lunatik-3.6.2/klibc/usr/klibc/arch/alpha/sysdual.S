#
# arch/alpha/sysdual.S
#

#
# Some system calls have an alternate return value in r20 (a4).
# This system call stub is for system calls where that is
# the "real" return value.
#

#include <machine/asm.h>

	.text
	.align	3
	.type	__syscall_dual1,@function
	.ent	__syscall_dual1, 0
	.globl	__syscall_dual1
__syscall_dual1:
	.frame	sp,0,ra,0
	callsys
	beq	a3, 1f
	br	pv, 2f			# pv <- pc
2:
	ldgp	gp, 0(pv)
	lda	a1, errno
	stl	v0, 0(a1)
	lda	a4, -1(zero)
1:
	mov	a4, v0
	ret	zero,(ra),1

	.size	__syscall_dual1,.-__syscall_dual1
	.end	__syscall_dual1
