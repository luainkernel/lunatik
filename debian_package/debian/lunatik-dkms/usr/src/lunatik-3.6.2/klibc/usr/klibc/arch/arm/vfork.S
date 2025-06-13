/*
 * arch/arm/vfork.S
 *
 * vfork - nasty system call which must not use the stack.
 */

#include <klibc/asmmacros.h>
#include <asm/unistd.h>

	.type	vfork,#function
	.globl	vfork
#ifndef __thumb__

	.balign	4
vfork:
#ifdef	__ARM_EABI__
	mov	r3, r7
	mov	r7, # __NR_vfork
	swi	0
	mov	r7, r3
#else
	swi	# __NR_vfork
#endif
        cmn     r0, #4096
        rsbcs	r2, r0, #0
        ldrcs	r3, 1f
        mvncs	r0, #0
        strcs	r2, [r3]
	BX(lr)

	.balign 4
1:
	.word	errno

#else

	.thumb_func
	.balign	2
vfork:
	mov	r3, r7
	mov	r7, # __NR_vfork
	swi	0
	mov	r7, r3
	ldr	r1, 2f
	cmp	r0, r1
	bcc	1f
	ldr	r1, 3f
	neg	r2, r0
	mov	r0, #1
	str	r2, [r1]
	neg	r0, r0
1:
	BX(lr)

	.balign	4
2:
	.word	-4095
3:
	.word	errno

#endif
