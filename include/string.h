/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_string_h
#define lunatik_string_h

#include <linux/string.h>
#define strcoll(l,r)	strcmp((l),(r))

#if defined(CONFIG_FORTIFY_SOURCE) && !defined(unsafe_memcpy)
#define unsafe_memcpy(dst, src, bytes, justification)	__builtin_memcpy(dst, src, bytes)
#endif

#endif

