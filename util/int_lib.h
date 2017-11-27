/*
 * This file is Confidential Information of Cujo LLC.
 * Copyright (c) 2017 CUJO LLC. All rights reserved.
 */

/* mock file to compile LLVM's modti3 in Linux kernel */

#ifndef int_lib_h
#define int_lib_h

#ifndef __LP64__
#include <linux/math64.h>

#define CRT_HAS_128BIT

#define COMPILER_RT_ABI
#define ti_int 		s64
#define tu_int 		u64
#define __udivmodti4 	div64_u64_rem
#define CHAR_BIT	(8)
#endif /* __LP64__ */

#endif /* int_lib_h */
