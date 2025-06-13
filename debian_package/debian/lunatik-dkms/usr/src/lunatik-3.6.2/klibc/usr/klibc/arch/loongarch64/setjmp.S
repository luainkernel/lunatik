/*
 * arch/loongarch64/setjmp.S
 *
 * setjmp/longjmp for the LoongArch64 architecture
 *
 * The jmp_buf is assumed to contain the following, in order:
 *	pc (ra)
 *	sp
 *	r21
 *	fp
 *	s0..s8
 */

#include <machine/asm.h>

ENTRY(setjmp)
	st.d	$ra,  $a0, 0
	st.d	$sp,  $a0, 8
	st.d	$r21, $a0, 16
	st.d	$fp,  $a0, 24
	st.d	$s0,  $a0, 32
	st.d	$s1,  $a0, 40
	st.d	$s2,  $a0, 48
	st.d	$s3,  $a0, 56
	st.d	$s4,  $a0, 64
	st.d	$s5,  $a0, 72
	st.d	$s6,  $a0, 80
	st.d	$s7,  $a0, 88
	st.d	$s8,  $a0, 96
	move	$a0,  $zero
	jr	$ra
END(setjmp)

ENTRY(longjmp)
	ld.d	$ra,  $a0, 0
	ld.d	$sp,  $a0, 8
	ld.d	$r21, $a0, 16
	ld.d	$fp,  $a0, 24
	ld.d	$s0,  $a0, 32
	ld.d	$s1,  $a0, 40
	ld.d	$s2,  $a0, 48
	ld.d	$s3,  $a0, 56
	ld.d	$s4,  $a0, 64
	ld.d	$s5,  $a0, 72
	ld.d	$s6,  $a0, 80
	ld.d	$s7,  $a0, 88
	ld.d	$s8,  $a0, 96
	move	$a0,  $a1
	jr	$ra
END(longjmp)
