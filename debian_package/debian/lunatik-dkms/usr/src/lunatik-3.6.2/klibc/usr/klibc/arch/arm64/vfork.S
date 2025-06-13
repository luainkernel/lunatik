/*
 * arch/arm64/vfork.S
 *
 * vfork - a system call which must not use the stack.
 */

#include <asm/unistd.h>

	.type	vfork,#function
	.globl	vfork
	.balign	8

vfork:
	/* Prepare for the system call */
        /* 1. Push the function pointer and argument location
              on to the child process stack */
        /* 2. Gather the Flags */
        /* New sp is already in x1.  */
        mov     x0, #0x4111     /* CLONE_VM | CLONE_VFORK | SIGCHLD */
        mov     x1, sp
        mov     w8,__NR_clone
        svc     0
        cmp     x0, #0x0
        b.ge    2f
        neg     x0, x0
        ldr     x8, 1f
        str     x0, [x8]
        mov     x0, #-1
2:
        ret
1:
        .dword   errno
        .size   vfork,.-vfork
