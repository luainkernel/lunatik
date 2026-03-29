/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_stdarg_h
#define lunatik_stdarg_h

#include <linux/version.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 17, 0)
#include <linux/stdarg.h>
#else
typedef __builtin_va_list va_list;
#define va_start(ap, last)	__builtin_va_start(ap, last)
#define va_end(ap)		__builtin_va_end(ap)
#define va_arg(ap, type)	__builtin_va_arg(ap, type)
#define va_copy(dst, src)	__builtin_va_copy(dst, src)
#endif

#endif

