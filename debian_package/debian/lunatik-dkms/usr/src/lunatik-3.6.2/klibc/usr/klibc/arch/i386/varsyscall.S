/*
 * arch/i386/varsyscall.S
 *
 * Common tail-handling code for varadic system calls (which always
 * use the cdecl convention.)
 *
 * The arguments are on the stack; the system call number in %eax.
 */

#ifdef	_REGPARM

#define ARG(n)	(4*n+24)(%esp)
#define SYSNO	ARG(-2)

	.text
	.align	4
	.globl	__syscall_varadic
	.type	__syscall_varadic,@function
__syscall_varadic:
	pushl	%ebx
	pushl	%esi
	pushl	%edi
	pushl	%ebp

	movl	SYSNO,%eax
	movl	ARG(0),%ebx		# Syscall arguments
	movl	ARG(1),%ecx
	movl	ARG(2),%edx
	movl	ARG(3),%esi
	movl	ARG(4),%edi
	movl	ARG(5),%ebp

	jmp	__syscall_common_tail

	.size	__syscall_varadic,.-__syscall_varadic

#endif
