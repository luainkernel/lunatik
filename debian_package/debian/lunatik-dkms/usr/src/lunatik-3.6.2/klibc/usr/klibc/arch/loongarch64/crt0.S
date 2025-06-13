#
# arch/loongarch64/crt0.S
#
# Does arch-specific initialization and invokes __libc_init
# with the appropriate arguments.
#
# See __static_init.c or __shared_init.c for the expected
# arguments.
#

#include <machine/asm.h>

ENTRY(_start)
	move		$a0, $sp		# Pointer to ELF entry structure
	move		$a1, $zero		# No onexit pointer
	bstrins.d	$sp, $zero, 3, 0	# Align stack to 16 bytes
	bl		__libc_init
END(_start)
