#include <machine/asm.h>
#include <asm/unistd.h>

ENTRY(__syscall_common)
	syscall 0
	li.w	$t0, -4096
	bleu	$a0, $t0, 1f
	sub.d	$a0, $zero, $a0
	la	$t0, errno
	st.d	$a0, $t0, 0
	li.w	$a0, -1
1:	jr	$ra
END(__syscall_common)
