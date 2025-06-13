#
# arch/ia64/syscall.S
#

#include <asm/unistd.h>

	.text
	.align	32
	.proc	__syscall_error
	.globl	__syscall_error
__syscall_error:
	movl	r2 = errno
	;;
	st4	[r2] = r8
	mov	r8 = -1
	br.ret.sptk.many b0
	.size	__syscall_error, .-__syscall_error
	.endp	__syscall_error
