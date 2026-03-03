/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_limits_h
#define lunatik_limits_h

#include <linux/limits.h>

#define UCHAR_MAX	(255)
#define CHAR_BIT	(8)

/**
 * vdso/limits.h defines INT_MAX as ((int)(~0U >> 1)) which breaks
 * "#if MAX_CNST/(MAXARG_vC + 1) > MAXARG_Ax" on lparser.c
 * see https://gcc.gnu.org/onlinedocs/cpp/If.html
 **/
#undef INT_MAX
#define INT_MAX	(2147483647)

#endif

