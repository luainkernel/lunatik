/*
 * arch/riscv64/setjmp.S
 *
 * setjmp/longjmp for the RISC-V (RV64) architecture
 *
 * The jmp_buf is assumed to contain the following, in order:
 *	pc (ra)
 *	s0..s11
 *	sp
 */

#include <machine/asm.h>

ENTRY(setjmp)
	sd	ra, 0(a0)
	sd	s0, 8(a0)
	sd	s1, 16(a0)
	sd	s2, 24(a0)
	sd	s3, 32(a0)
	sd	s4, 40(a0)
	sd	s5, 48(a0)
	sd	s6, 56(a0)
	sd	s7, 64(a0)
	sd	s8, 72(a0)
	sd	s9, 80(a0)
	sd	s10, 88(a0)
	sd	s11, 96(a0)
	sd	sp, 104(a0)
	mv	a0, zero
	jr	ra
END(setjmp)

ENTRY(longjmp)
	ld	ra, 0(a0)
	ld	s0, 8(a0)
	ld	s1, 16(a0)
	ld	s2, 24(a0)
	ld	s3, 32(a0)
	ld	s4, 40(a0)
	ld	s5, 48(a0)
	ld	s6, 56(a0)
	ld	s7, 64(a0)
	ld	s8, 72(a0)
	ld	s9, 80(a0)
	ld	s10, 88(a0)
	ld	s11, 96(a0)
	ld	sp, 104(a0)
	mv	a0, a1
	jr	ra
END(longjmp)
