#
# arch/mips/crt0.S
#
# Does arch-specific initialization and invokes __libc_init
# with the appropriate arguments.
#
# See __static_init.c or __shared_init.c for the expected
# arguments.
#

#include <machine/asm.h>

NESTED(__start, 0, ra)
	move	a0, sp			# Pointer to ELF entry structure
	move	a1, v0			# Kernel-provided atexit() pointer
	and	sp, -8			# Align stack to 8 bytes
	subu	sp, 16			# Allocate 16 bytes for function call

	jal	__libc_init
	teq	zero, zero		# Crash if we return

	END(__start)
