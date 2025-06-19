/*
 * usr/include/arch/arm/klibc/asmmacros.h
 *
 * Assembly macros used by ARM system call stubs
 */

#ifndef _KLIBC_ASMMACROS_H
#define _KLIBC_ASMMACROS_H

#if _KLIBC_ARM_USE_BX
# define BX(x) bx	x
#else
# define BX(x) mov	pc, x
#endif

#endif /* _KLIBC_ASMMACROS_H */
