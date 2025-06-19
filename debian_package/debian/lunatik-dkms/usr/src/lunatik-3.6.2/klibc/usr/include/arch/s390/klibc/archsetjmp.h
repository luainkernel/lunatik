/*
 * arch/s390/include/klibc/archsetjmp.h
 */

#ifndef _KLIBC_ARCHSETJMP_H
#define _KLIBC_ARCHSETJMP_H

#ifndef __s390x__

struct __jmp_buf {
	uint32_t __gregs[10];	/* general registers r6-r15 */
	uint64_t __fpregs[2];	/* fp registers f4 and f6   */
};

#else /* __s390x__ */

struct __jmp_buf {
	uint64_t __gregs[10]; /* general registers r6-r15 */
	uint64_t __fpregs[8]; /* fp registers f8-f15 */
};

#endif /* __s390x__ */

typedef struct __jmp_buf jmp_buf[1];

#endif				/* _SETJMP_H */
