/*
 * arch/riscv64/include/klibc/archsetjmp.h
 */

#ifndef _KLIBC_ARCHSETJMP_H
#define _KLIBC_ARCHSETJMP_H

struct __jmp_buf {
	unsigned long __pc;
	unsigned long __s0;
	unsigned long __s1;
	unsigned long __s2;
	unsigned long __s3;
	unsigned long __s4;
	unsigned long __s5;
	unsigned long __s6;
	unsigned long __s7;
	unsigned long __s8;
	unsigned long __s9;
	unsigned long __s10;
	unsigned long __s11;
	unsigned long __sp;
};

typedef struct __jmp_buf jmp_buf[1];

#endif				/* _SETJMP_H */
