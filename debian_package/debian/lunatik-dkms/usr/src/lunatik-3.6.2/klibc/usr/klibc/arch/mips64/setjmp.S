#
# arch/mips64/setjmp.S
#
# setjmp/longjmp for the MIPS architecture
#
# The jmp_buf is assumed to contain the following, in order:
#	s0..s7
#	gp
#	sp
#	s8
#	ra
#

#include <machine/asm.h>

LEAF(setjmp)
	sd	s0,  0(a0)
	sd	s1,  8(a0)
	sd	s2, 16(a0)
	sd	s3, 24(a0)
	sd	s4, 32(a0)
	sd	s5, 40(a0)
	sd	s6, 48(a0)
	sd	s7, 56(a0)
	sd	gp, 64(a0)
	sd	sp, 72(a0)
	sd	s8, 80(a0)
	sd	ra, 88(a0)
	move	v0, zero
	jr	ra

	END(setjmp)

LEAF(longjmp)
	ld	s0,  0(a0)
	ld	s1,  8(a0)
	ld	s2, 16(a0)
	ld	s3, 24(a0)
	ld	s4, 32(a0)
	ld	s5, 40(a0)
	ld	s6, 48(a0)
	ld	s7, 56(a0)
	ld	gp, 64(a0)
	ld	sp, 72(a0)
	ld	s8, 80(a0)
	ld	ra, 88(a0)
	move	v0, a1
	jr	ra

	END(longjmp)
