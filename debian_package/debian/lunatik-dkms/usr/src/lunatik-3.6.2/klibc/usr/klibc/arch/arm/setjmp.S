#
# arch/arm/setjmp.S
#
# setjmp/longjmp for the ARM architecture
#

#include <klibc/asmmacros.h>

#ifndef	__thumb__

#
# "Pure ARM" version
#
# The jmp_buf is assumed to contain the following, in order:
#		r4
#		r5
#		r6
#		r7
#		r8
#		r9
#		r10
#		fp
#		sp
#		lr
#

	.text
	.balign 4
	.globl setjmp
	.type setjmp, #function
setjmp:
	stmia	r0, {r4, r5, r6, r7, r8, r9, r10, fp, sp, lr}
	mov	r0, #0
	BX(lr)
	.size setjmp,.-setjmp

	.text
	.balign 4
	.globl longjmp
	.type longjmp, #function
longjmp:
	ldmia	r0, {r4, r5, r6, r7, r8, r9, r10, fp, sp, lr}
	movs	r0, r1
	moveq	r0, #1
	BX(lr)
	.size longjmp,.-longjmp

#else /* __thumb__ */

#
# Thumb version
#
# The jmp_buf is assumed to contain the following, in order:
#		lr
#		r4
#		r5
#		r6
#		r7
#		r8
#		r9
#		r10
#		fp
#		sp
#

	.text
	.balign 4
	.globl setjmp
	.type setjmp, #function
	.thumb_func
setjmp:
	mov	r2, r0
	mov	r3, lr
	stmia	r0!, {r3, r4, r5, r6, r7}
	mov	r3, r8
	mov	r4, r9
	mov	r5, r10
	mov	r6, fp
	mov	r7, sp
	stmia	r0!, {r3, r4, r5, r6, r7}
	/* Do not trash r4 .. r7 */
	ldmia	r2!, {r3, r4, r5, r6, r7}
	mov	r0, #0
	BX(lr)
	.size setjmp,.-setjmp

	.text
	.balign 4
	.globl longjmp
	.type longjmp, #function
	.thumb_func
longjmp:
	mov	r2, r0
	add	r0, #5*4
	ldmia	r0!, {r3, r4, r5, r6, r7}
	mov	r8, r3
	mov	r9, r4
	mov	r10, r5
	mov	fp, r6
	mov	sp, r7
	ldmia	r2!, {r3, r4, r5, r6, r7}
	mov	r0, r1
	bne	1f
	mov	r0, #1
1:	BX(r3)
	.size longjmp,.-longjmp

#endif /* __thumb__ */
