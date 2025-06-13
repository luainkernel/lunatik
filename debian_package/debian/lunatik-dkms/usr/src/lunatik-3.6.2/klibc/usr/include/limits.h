/*
 * limits.h
 */

#ifndef _LIMITS_H
#define _LIMITS_H

/* No multibyte characters seen */
#define MB_LEN_MAX 1

#define OPEN_MAX        256

#define CHAR_BIT	8
#define SHRT_BIT	16
#define INT_BIT		32
#define LONGLONG_BIT	64

#define SCHAR_MIN	(-128)
#define SCHAR_MAX	127
#define UCHAR_MAX	255

#ifdef __CHAR_UNSIGNED__
# define CHAR_MIN 0
# define CHAR_MAX UCHAR_MAX
#else
# define CHAR_MIN SCHAR_MIN
# define CHAR_MAX SCHAR_MAX
#endif

#define SHRT_MIN	(-32768)
#define SHRT_MAX	32767
#define USHRT_MAX	65535

#define INT_MIN		(-2147483647-1)
#define INT_MAX		2147483647
#define UINT_MAX	4294967295U

#define LLONG_MIN	(-9223372036854775807LL-1)
#define LLONG_MAX	9223372036854775807LL
#define ULLONG_MAX	18446744073709551615ULL

#include <bitsize/limits.h>
#include <linux/limits.h>

#define SSIZE_MAX	LONG_MAX

#endif				/* _LIMITS_H */
