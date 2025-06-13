#
# usr/klibc/arch/x86_64/vfork.S
#
# vfork is nasty - there must be nothing at all on the stack above
# the stack frame of the enclosing function.
#

#include <asm/unistd.h>

	.text
	.align	4
	.globl	vfork
	.type	vfork, @function
vfork:
	pop	%rdx			/* Return address */
	movl	$__NR_vfork, %eax
	syscall
	push	%rdx
	cmpq	$-4095, %rax
	jae	1f
	ret
1:
	negl	%eax
	movl	%eax, errno(%rip)
	orq	$-1, %rax
	ret
