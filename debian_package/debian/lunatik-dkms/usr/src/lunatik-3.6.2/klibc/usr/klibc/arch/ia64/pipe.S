#include <asm/unistd.h>
	.align 32
	.proc pipe
	.global pipe
pipe:
	alloc r16 = ar.pfs, 1, 0, 8, 0
	mov r33 = r32
	mov	r15=__NR_pipe
	;;
	break 0x100000	// Do the syscall
	;;

	cmp.ne p6, p7 = -1, r10
	mov r15 = r0
	;;
(p6)	st4 [r32] = r8, 4

(p7)	movl r14 = errno
(p7)	addl r15 = -1, r0
	;;
(p6)	st4 [r32] = r9

(p7)	st4 [r14] = r8

	mov r8 = r15
	br.ret.sptk.many b0
	.endp pipe
