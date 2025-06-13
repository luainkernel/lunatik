/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_limits_h
#define lunatik_limits_h

#include <linux/limits.h>

#define UCHAR_MAX	(255)
#define CHAR_BIT	(8)

/* vdso/limits.h defines UINT_MAX as (~0U) which might expands to 0xFFFFFFFFFFFFFFFF
 * in the '#if' directive [https://gcc.gnu.org/onlinedocs/cpp/If.html] which breaks
 * "#if (UINT_MAX >> 30) > 3" on ltable.c */
#undef UINT_MAX
#define UINT_MAX	(4294967295U)

#endif

