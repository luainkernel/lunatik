/*
 * This file is Confidential Information of Cujo LLC.
 * Copyright (c) 2018 CUJO LLC. All rights reserved.
 */

/* mock file to compile LLVM's modti3 and udivmodti4 in Linux kernel */

#ifndef int_lib_h
#define int_lib_h

#ifndef __LP64__
#include <linux/compiler.h>
#include <linux/math64.h>
#include <linux/version.h>
#include <asm-generic/bitops/ffs.h>
#include <asm-generic/bitops/fls.h>

#define CRT_HAS_128BIT

#define COMPILER_RT_ABI
#define ti_int 		s64
#define tu_int 		u64
#define __udivmodti4 	div64_u64_rem
#define CHAR_BIT	(8)

#if LINUX_VERSION_CODE < KERNEL_VERSION(3,12,0)

#define __builtin_clzll(x) (32 - fls(x))
#define __builtin_ctzll(x) (x ? ffs(x) - 1 : 32)

#define su_int	u16
#define du_int	u32

typedef union {
    tu_int all;
    struct {
#ifdef __LITTLE_ENDIAN
        du_int low;
        du_int high;
#else
        du_int high;
        du_int low;
#endif /* __LITTLE_ENDIAN */
    } s;
} utwords;

extern u64 div64_u64_rem(u64 dividend, u64 divisor, u64 *remainder);

#endif /* LINUX_VERSION_CODE < KERNEL_VERSION(3,12,0) */

#endif /* __LP64__ */

#endif /* int_lib_h */
