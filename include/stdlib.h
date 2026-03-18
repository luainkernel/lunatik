/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_stdlib_h
#define lunatik_stdlib_h

#include <linux/slab.h>
#define abort()		BUG()
#define free(a)		kfree((a))
#define realloc(a,b)	krealloc((a),(b),GFP_KERNEL)
static inline char *getenv(const char *name)
{
	(void)name;
	return NULL;
}

#endif

