/*
 * arch/m68k/syscall.S
 *
 * Common tail-handling code for system calls.
 *
 * The arguments are on the stack; the system call number in %d0.
 */

	.text
	.align	2
	.globl	__syscall_common
	.type	__syscall_common, @function
__syscall_common:
	/*
	 * According to eglibc, separate moves are faster than movem;
	 * speed is important and this code is not duplicated anyway,
	 * so we do the same here. We use %a1 as scratch register for
	 * saving; syscall arguments are to be in %d1 to %d5 and %a0.
	 */
	move.l	24(%sp), %a0		/* orig.sp+24: arg 6 */
	move.l	%d5, -(%sp)		/* push d5 (callee saved) */
	move.l	24(%sp), %d5		/* orig.sp+20: arg 5 */
	move.l	%d4, -(%sp)		/* push d4 (callee saved) */
	move.l	24(%sp), %d4		/* orig.sp+16: arg 4 */
	move.l	%d3, -(%sp)		/* push d3 (callee saved) */
	move.l	24(%sp), %d3		/* orig.sp+12: arg 3 */
	move.l	%d2, %a1		/* save d2 (callee saved) in a1 */
	move.l	20(%sp), %d2		/* orig.sp+8:  arg 2 */
	move.l	16(%sp), %d1		/* orig.sp+4:  arg 1 */
	trap	#0
	move.l	%a1, %d2		/* restore d2 from a1 (scratch) */
	move.l	(%sp)+, %d3		/* pop d3..d5, see above */
	move.l	(%sp)+, %d4
	move.l	(%sp)+, %d5

	/* syscall is done, result in %d0, registers are restored */
	.globl	__syscall_checkandout
__syscall_checkandout:
	/* now check for error */
	cmp.l	#-4095, %d0
	bcs.l	1f			/* jump if _not_ error */

	/* prepare for error return */
	neg.l	%d0
	move.l	%d0, (errno)
	move.l	#-1, %d0
	/* fallthrough into common return path */

1:	/* copy return value to %a0 for syscalls returning pointers */
	move.l	%d0, %a0
	rts

	.size	__syscall_common,.-__syscall_common
