/* Copyright (c) 2002 H. Peter Anvin <hpa@zytor.com> */

/* SPDX-License-Identifier: GPL-2.0 */
#
# arch/x86/setjmp.S
#
# setjmp/longjmp for the i386 and x86-64 architectures
#

#
# The jmp_buf is assumed to contain the following, in order:
#	%ebx
#	%esp
#	%ebp
#	%esi
#	%edi
#	<return address>
#

	.text
	.align 4
	.globl setjmp
	.type setjmp, @function
setjmp:
#ifdef _REGPARM
	movl %eax,%edx
#else
	movl 4(%esp),%edx
#endif
	popl %ecx			# Return address, and adjust the stack
	xorl %eax,%eax			# Return value
	movl %ebx,(%edx)
	movl %esp,4(%edx)		# Post-return %esp!
	pushl %ecx			# Make the call/return stack happy
	movl %ebp,8(%edx)
	movl %esi,12(%edx)
	movl %edi,16(%edx)
	movl %ecx,20(%edx)		# Return address
	ret

	.size setjmp,.-setjmp

	.text
	.align 4
	.globl longjmp
	.type longjmp, @function
longjmp:
#ifdef _REGPARM
	xchgl %eax,%edx
#else
	movl 4(%esp),%edx		# jmp_ptr address
	movl 8(%esp),%eax		# Return value
#endif
	movl (%edx),%ebx
	movl 4(%edx),%esp
	movl 8(%edx),%ebp
	movl 12(%edx),%esi
	movl 16(%edx),%edi
	jmp *20(%edx)

	.size longjmp,.-longjmp

#
# The jmp_buf is assumed to contain the following, in order:
#	%rbx
#	%rsp (post-return)
#	%rbp
#	%r12
#	%r13
#	%r14
#	%r15
#	<return address>
#

	.text
	.align 4
	.globl setjmp
	.type setjmp, @function
setjmp:
	pop  %rsi			# Return address, and adjust the stack
	xorl %eax,%eax			# Return value
	movq %rbx,(%rdi)
	movq %rsp,8(%rdi)		# Post-return %rsp!
	push %rsi			# Make the call/return stack happy
	movq %rbp,16(%rdi)
	movq %r12,24(%rdi)
	movq %r13,32(%rdi)
	movq %r14,40(%rdi)
	movq %r15,48(%rdi)
	movq %rsi,56(%rdi)		# Return address
	ret

	.size setjmp,.-setjmp

	.text
	.align 4
	.globl longjmp
	.type longjmp, @function
longjmp:
	movl %esi,%eax			# Return value (int)
	movq (%rdi),%rbx
	movq 8(%rdi),%rsp
	movq 16(%rdi),%rbp
	movq 24(%rdi),%r12
	movq 32(%rdi),%r13
	movq 40(%rdi),%r14
	movq 48(%rdi),%r15
	jmp *56(%rdi)

	.size longjmp,.-longjmp
