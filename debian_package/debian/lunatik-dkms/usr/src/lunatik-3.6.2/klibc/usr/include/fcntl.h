/*
 * fcntl.h
 */

#ifndef _FCNTL_H
#define _FCNTL_H

#include <klibc/extern.h>
#include <klibc/compiler.h>
#include <klibc/seek.h>
#include <sys/types.h>
#if defined(__mips__) && ! defined(__mips64)
# include <klibc/archfcntl.h>
#elif _BITSIZE == 32
/* We want a struct flock with 64-bit offsets, which we define below */
# define HAVE_ARCH_STRUCT_FLOCK
#endif
#include <linux/fcntl.h>
#include <bitsize.h>

#if !defined(__mips__) && _BITSIZE == 32

/*
 * <linux/fcntl.h> defines struct flock with offsets of type
 * __kernel_off_t (= long) and struct flock64 with offsets of
 * type __kernel_loff_t (= long long).  We want struct flock
 * to have 64-bit offsets, so we define it here.
 */

struct flock {
	short  l_type;
	short  l_whence;
	__kernel_loff_t l_start;
	__kernel_loff_t l_len;
	__kernel_pid_t  l_pid;
#ifdef __ARCH_FLOCK64_PAD
        __ARCH_FLOCK64_PAD
#endif
};

#ifdef F_GETLK64
# undef F_GETLK
# define F_GETLK F_GETLK64
#endif

#ifdef F_SETLK64
# undef F_SETLK
# define F_SETLK F_SETLK64
#endif

#ifdef F_SETLKW64
# undef F_SETLKW
# define F_SETLKW F_SETLKW64
#endif

#endif /* _BITSIZE == 32 */

/* This is defined here as well as in <unistd.h> */
#ifndef _KLIBC_IN_OPEN_C
__extern int open(const char *, int, ...);
__extern int openat(int, const char *, int, ...);
#endif

__extern int creat(const char *, mode_t);
__extern int fcntl(int, int, ...);

#endif				/* _FCNTL_H */
