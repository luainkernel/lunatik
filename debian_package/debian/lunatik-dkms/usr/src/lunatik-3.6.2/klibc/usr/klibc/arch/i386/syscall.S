/*
 * arch/i386/syscall.S
 *
 * Common tail-handling code for system calls.
 *
 * The arguments are on the stack; the system call number in %eax.
 */

#define ARG(n)	(4*(n)+24)(%esp)
#define SYSNO	ARG(-2)

	.text
	.align	4
	.globl	__syscall_common
	.type	__syscall_common,@function
__syscall_common:
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	pushl	%ebp

#ifdef _REGPARM
	xchgl	%ecx,%edx
	movl	%eax,%ebx
	movl	SYSNO,%eax
	movl	ARG(0),%esi
	movl	ARG(1),%edi
	movl	ARG(2),%ebp
#else
	movl	SYSNO,%eax
	movl	ARG(0),%ebx		# Syscall arguments
	movl	ARG(1),%ecx
	movl	ARG(2),%edx
	movl	ARG(3),%esi
	movl	ARG(4),%edi
	movl	ARG(5),%ebp
#endif
	.globl __syscall_common_tail
__syscall_common_tail:
	call	*__syscall_entry

	cmpl	$-4095,%eax

	popl	%ebp
	popl	%edi
	popl	%esi
	popl	%ebx
	popl	%edx			# Drop system call number

	jb	1f

	# Error return, must set errno
	negl	%eax
	movl	%eax,errno
	orl	$-1,%eax		# Return -1

1:
	ret

	.size	__syscall_common,.-__syscall_common

#ifndef _REGPARM

	.globl	__syscall_varadic
	.type	__syscall_varadic,@function
__syscall_varadic = __syscall_common

#endif

	.align	4
__syscall_int80:
	int	$0x80
	ret
	.type	__syscall_int80,@function
	.size	__syscall_int80,.-__syscall_int80

	.data
	.align	4
	.globl	__syscall_entry
__syscall_entry:
	.long	__syscall_int80
	.size	__syscall_entry,.-__syscall_entry
