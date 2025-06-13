/*
 * arch/arm64/syscall.S
 *
 * System call common handling - if the return
 * value from the system call is negative, then
 * extract the magnitude and return it as errno and
 * return -1, if the return value is 0 that is
 * success case.
 */

	.type	__syscall_common,#function
	.globl  __syscall_common
	.balign 8

__syscall_common:
	cmp	x0, #0x0
	b.ge	2f
	neg	x0, x0
	ldr	x8, 1f
	str	w0, [x8]
	mov	x0, #-1
2:
	ret
1:
	.dword	errno
