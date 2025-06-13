/*
 * sys/types.h
 */

#ifndef _SYS_TYPES_H
#define _SYS_TYPES_H

#include <klibc/compiler.h>
#include <stddef.h>
#include <stdint.h>

#define _SSIZE_T
/* __SIZE_TYPE__ defined either by GCC or <stddef.h> */
#define unsigned /* nothing, temporarily */
typedef signed __SIZE_TYPE__ ssize_t;
#undef unsigned

#include <linux/posix_types.h>
#include <asm/types.h>

/* Keeps linux/types.h from getting included elsewhere */
#define _LINUX_TYPES_H

typedef __kernel_fd_set fd_set;
typedef uint32_t dev_t;
typedef __kernel_ino_t ino_t;
typedef __kernel_mode_t mode_t;
typedef __kernel_loff_t off_t;
typedef __kernel_loff_t loff_t;
typedef __kernel_pid_t pid_t;
typedef __kernel_daddr_t daddr_t;
typedef __kernel_key_t key_t;
typedef __kernel_suseconds_t suseconds_t;
/* typedef __kernel_timer_t	timer_t; */
typedef int timer_t;
typedef __kernel_clockid_t clockid_t;

typedef __kernel_uid32_t uid_t;
typedef __kernel_gid32_t gid_t;

typedef __kernel_fsid_t fsid_t;

/*
 * The following typedefs are also protected by individual ifdefs for
 * historical reasons:
 */
#ifndef _TIME_T
#define _TIME_T
typedef __kernel_time64_t time_t;
#endif

#ifndef _CLOCK_T
#define _CLOCK_T
typedef __kernel_clock_t clock_t;
#endif

#ifndef _CADDR_T
#define _CADDR_T
typedef __kernel_caddr_t caddr_t;
#endif

/* BSD */
typedef unsigned char u_char;
typedef unsigned short u_short;
typedef unsigned int u_int;
typedef unsigned long u_long;

/* SysV */
typedef unsigned char unchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;

/* More BSD */
typedef uint8_t u_int8_t;
typedef uint16_t u_int16_t;
typedef uint32_t u_int32_t;
typedef uint64_t u_int64_t;

typedef __u16 __bitwise __le16;
typedef __u16 __bitwise __be16;
typedef __u32 __bitwise __le32;
typedef __u32 __bitwise __be32;
typedef __u64 __bitwise __le64;
typedef __u64 __bitwise __be64;

typedef __u16 __bitwise __sum16;
typedef __u32 __bitwise __sum32;
typedef __u64 __bitwise __sum64;
typedef __u32 __bitwise __wsum;

#define __aligned_u64 __u64 __attribute__((aligned(8)))
#define __aligned_be64 __be64 __attribute__((aligned(8)))
#define __aligned_le64 __le64 __attribute__((aligned(8)))

/*
 * Some headers seem to require this...
 */
#ifndef BITS_PER_LONG
# define BITS_PER_LONG _BITSIZE
#endif

/*
 * Some apps want this in <sys/types.h>
 */
#include <sys/sysmacros.h>

#endif
