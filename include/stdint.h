/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_stdint_h
#define lunatik_stdint_h

#include <linux/types.h>

#if BITS_PER_LONG == 32
uint64_t __udivmoddi4(uint64_t num, uint64_t den, uint64_t *rem);
int64_t __divdi3(int64_t num, int64_t den);
uint64_t __udivdi3(uint64_t num, uint64_t den);
int64_t __moddi3(int64_t num, int64_t den);
uint64_t __umoddi3(uint64_t num, uint64_t den);
#endif /* BITS_PER_LONG = 32 */
#endif

