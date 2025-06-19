/*
 * arch/i386/include/klibc/archinit.h
 *
 * Architecture-specific libc initialization
 */

#include <stdint.h>
#include <klibc/compiler.h>
#include <elf.h>
#include <sys/auxv.h>

extern void (*__syscall_entry)(int, ...);

static inline void __libc_archinit(void)
{
	if (__auxval[AT_SYSINFO])
		__syscall_entry = (void (*)(int, ...)) __auxval[AT_SYSINFO];
}
