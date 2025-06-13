/*
 * usr/include/arch/m68k/klibc/archsetjmp.h
 */

#ifndef _KLIBC_ARCHSETJMP_H
#define _KLIBC_ARCHSETJMP_H

struct __jmp_buf {
	unsigned int __d2;
	unsigned int __d3;
	unsigned int __d4;
	unsigned int __d5;
	unsigned int __d6;
	unsigned int __d7;
	unsigned int __a2;
	unsigned int __a3;
	unsigned int __a4;
	unsigned int __a5;
	unsigned int __fp;	/* a6 */
	unsigned int __sp;	/* a7 */
	unsigned int __retaddr;
};

typedef struct __jmp_buf jmp_buf[1];

#endif				/* _KLBIC_ARCHSETJMP_H */
