/*
* Copyright (c) 2023 ring-0 Ltda.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#ifndef arch_setjmp_h
#define arch_setjmp_h

#if defined(CONFIG_X86_32)
#include "x86/archsetjmp_32.h"
#elif defined(CONFIG_X86_64)
#include "x86/archsetjmp_64.h"
#else
/* TODO: jmp_buf should be defined per platform */
#define JMP_BUF_MAX	(14) /* MIPS */
typedef	unsigned long long __jmp_regmax_t;
struct __jmp_buf {
	__jmp_regmax_t regs[JMP_BUF_MAX];
};
typedef struct __jmp_buf jmp_buf[1];
#endif

#endif

