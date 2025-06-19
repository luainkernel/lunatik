#include <machine/asm.h>
#include <asm/unistd.h>


LEAF(__syscall_common)
	syscall
        beqz    a3, 1f
        sw      v0, errno
        li      v0, -1
1:      jr      ra
	END(__syscall_common)
