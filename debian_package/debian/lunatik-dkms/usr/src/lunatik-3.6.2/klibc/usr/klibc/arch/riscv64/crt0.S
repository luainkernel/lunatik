#
# arch/riscv64/crt0.S
#
# Does arch-specific initialization and invokes __libc_init
# with the appropriate arguments.
#
# See __static_init.c or __shared_init.c for the expected
# arguments.
#

#include <machine/asm.h>

ENTRY(_start)
	.option push
	.option norelax
	lla	gp, __global_pointer$
	.option pop

	mv	a0, sp			# Pointer to ELF entry structure
	mv	a1, zero		# No onexit pointer
	jal	__libc_init
END(_start)
