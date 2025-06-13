#
# arch/mips64/crt0.S
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
	and	sp, -16			# Align stack to 16 bytes

	jal	__libc_init
	teq	zero, zero		# Crash if we return

	END(__start)
