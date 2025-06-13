
#include <asm/fpu.h>

	.align 32
	.global _start

	.proc _start
	.type _start,@function
_start:
	.prologue
	.save rp, r0

	alloc r2 = ar.pfs,0,0,2,0
	movl r3 = FPSR_DEFAULT
	;;
	adds out0= 16,sp    /* argc pointer */

	.body
	br.call.sptk.few rp = __libc_init
	;;
	break 0             /* break miserably if we ever return */

	.endp _start
