#
# arch/riscv64/_main.S
#
# Does arch-specific initialization and invokes main with the
# appropriate arguments.
#

#include <machine/asm.h>

ENTRY(_main)
	.option push
	.option norelax
	lla	gp, __global_pointer$
	.option pop

	j	main
END(_main)
