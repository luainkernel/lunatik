#
# arch/m68k/crt0.S
#
# Does arch-specific initialization and invokes __libc_init
# with the appropriate arguments.
#
# See __static_init.c or __shared_init.c for the expected
# arguments.
#

	.text
	.align 4
	.type _start,@function
	.globl _start
_start:
	# Zero out the frame pointer to be nice to the debugger
	movea.l	#0,%a6
	# Save the address of the ELF argument array
	move.l	%a7, %d0
	# Push a zero on the stack in lieu of atexit pointer
	clr.l	-(%sp)
	# Push ELF argument pointer on the stack
	move.l	%d0, -(%a7)

	jbsr	__libc_init

	.size _start, .-_start
