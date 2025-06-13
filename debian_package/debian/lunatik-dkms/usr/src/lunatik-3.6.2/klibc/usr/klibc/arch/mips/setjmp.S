#
# arch/mips/setjmp.S
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
	sw	s0,  0(a0)
	sw	s1,  4(a0)
	sw	s2,  8(a0)
	sw	s3, 12(a0)
	sw	s4, 16(a0)
	sw	s5, 20(a0)
	sw	s6, 24(a0)
	sw	s7, 28(a0)
	sw	gp, 32(a0)
	sw	sp, 36(a0)
	sw	s8, 40(a0)
	sw	ra, 44(a0)
	move	v0,zero
	jr	ra

	END(setjmp)

LEAF(longjmp)
	lw	s0,  0(a0)
	lw	s1,  4(a0)
	lw	s2,  8(a0)
	lw	s3, 12(a0)
	lw	s4, 16(a0)
	lw	s5, 20(a0)
	lw	s6, 24(a0)
	lw	s7, 28(a0)
	lw	gp, 32(a0)
	lw	sp, 36(a0)
	lw	s8, 40(a0)
	lw	ra, 44(a0)
	move	v0,a1
	jr	ra

	END(longjmp)
