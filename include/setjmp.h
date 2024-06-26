/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_setjmp_h
#define lunatik_setjmp_h

#include <linux/ctype.h>

#include <klibc/archconfig.h>
#include <klibc/archsetjmp.h>

extern int setjmp(jmp_buf);
extern void __attribute__((noreturn)) longjmp(jmp_buf, int);

#endif

