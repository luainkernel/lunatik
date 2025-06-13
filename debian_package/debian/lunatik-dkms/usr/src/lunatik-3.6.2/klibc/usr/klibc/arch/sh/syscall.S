/*
 * arch/sh/syscall.S
 *
 * On sh, r3 contains the syscall number (set by generated stub);
 * r4..r7 contain arguments 0-3 per the standard calling convention,
 * and arguments 4-5 are passed in r0 and r1.
 *
 * The return value is in r0.
 */

	.section ".text.syscall","ax"
	.align	2
	.globl	__syscall_common
	.type	__syscall_common,@function
__syscall_common:
	mov.l	@(0,sp),r0
	mov.l	@(4,sp),r1
	trapa	#0x15
	mov.l	1f,r1
	cmp/hs	r0,r1
	bt/s	3f
	  neg	r0,r1
	mov.l	2f,r2
	mov.l	r1,@r2
	rts
	  mov	#-1,r0
3:
	rts
	  nop

	.align 2
1:	.long	-4096		/* Errno limit */
2:	.long	errno

	.size	__syscall_common,.-__syscall_common
