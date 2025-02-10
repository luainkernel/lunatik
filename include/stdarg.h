/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_stdarg_h
#define lunatik_stdarg_h

#include <linux/version.h>

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)
#include <linux/stdarg.h>
#else
#include <stdarg.h>
#endif

#endif

