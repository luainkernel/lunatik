/*
 * arch/arm/syscall.S
 *
 * System call common handling
 */

	.type	__syscall_common,#function
	.globl	__syscall_common
#ifndef __thumb__
	/* ARM version - this is executed after the swi, unless
	   we are compiled in EABI mode */

	.balign	4
__syscall_common:
#ifdef __ARM_EABI__
	ldr	r4, [sp,#16]
	ldr	r5, [sp,#20]
	ldr	r7, [lr]
	swi	0
#endif
        cmn     r0, #4096
        rsbcs	r2, r0, #0
        ldrcs	r3, 1f
        mvncs	r0, #0
        strcs	r2, [r3]
#ifdef __ARM_EABI__
	ldmfd	sp!,{r4,r5,r7,pc}
#else
	ldmfd	sp!,{r4,r5,pc}
#endif

	.balign 4
1:
	.word	errno

#else
	/* Thumb version - must still load r4 and r5 and run swi */

	.thumb_func
	.balign	2
__syscall_common:
	mov	r7, lr
	ldr	r4, [sp,#16]
	sub	r7, #1		/* Remove the Thumb bit */
	ldr	r5, [sp,#20]
	ldrh	r7, [r7]
	swi	0
	ldr	r1, 2f
	cmp	r0, r1
	bcc	1f
	ldr	r1, 3f
	neg	r2, r0
	mov	r0, #1
	str	r2, [r1]
	neg	r0, r0
1:
	pop	{r4,r5,r7,pc}

	.balign	4
2:
	.word	-4095
3:
	.word	errno

#endif
