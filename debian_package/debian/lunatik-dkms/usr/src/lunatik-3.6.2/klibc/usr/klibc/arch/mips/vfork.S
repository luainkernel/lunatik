#include <machine/asm.h>
#include <asm/unistd.h>

#define CLONE_VM	0x00000100
#define CLONE_VFORK	0x00004000
#define SIGCHLD		18


LEAF(vfork)
	li	a0, CLONE_VFORK | CLONE_VM | SIGCHLD
	li	a1, 0
	li	v0, __NR_clone
	j	__syscall_common
	END(vfork)
