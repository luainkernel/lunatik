/*
 * arch/arm64/include/klibc/archsetjmp.h
 */

#ifndef _KLIBC_ARCHSETJMP_H
#define _KLIBC_ARCHSETJMP_H

/*
 * x18 may be used as a platform register (e.g., shadow call stack).
 * x19-x28 are callee saved, also save fp, lr, sp.
 * d8-d15 are unused as we specify -mgeneral-regs-only as a build flag.
 */

struct __jmp_buf {
	uint64_t __x18, __x19, __x20, __x21;
	uint64_t __x22, __x23, __x24, __x25;
	uint64_t __x26, __x27, __x28, __x29;
	uint64_t __x30, __sp;
};

typedef struct __jmp_buf jmp_buf[1];

#endif				/* _SETJMP_H */
