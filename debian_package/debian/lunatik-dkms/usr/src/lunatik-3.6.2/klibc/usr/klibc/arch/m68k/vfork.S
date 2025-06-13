#
# usr/klibc/arch/m68k/vfork.S
#
# vfork is nasty - there must be nothing at all on the stack above
# the stack frame of the enclosing function.
#

#include <asm/unistd.h>

	.text
	.align	2
	.globl	vfork
	.type	vfork, @function
vfork:
	move.l	(%sp)+, %d1		/* Return address */
	move.l	# __NR_vfork, %d0
	trap	#0
	move.l	%d1, -(%sp)		/* restore stack */

	/* fallthrough into common code from syscall.S */
	bra	__syscall_checkandout

	.size	vfork, .-vfork
