#include <machine/asm.h>
#include <asm/unistd.h>

ENTRY(__syscall_common)
	scall
	li	t0, -4096
	bleu	a0, t0, 1f
	neg	a0, a0
	lui	t0, %hi(errno)
	sw	a0, %lo(errno)(t0)
	li	a0, -1
1:	jr	ra
END(__syscall_common)
