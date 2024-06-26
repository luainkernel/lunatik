/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
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

/* used only for readable() @ lua/loadlib.c */
#ifdef loadlib_c
#include <linux/fs.h>
typedef struct file FILE;
static inline struct file *fopen(const char *name, const char *mode)
{
	struct file *f;
	(void)mode;
	if (unlikely(name == NULL) || IS_ERR(f = filp_open(name, O_RDONLY, 0600)))
		return NULL;
	return f;
}
#define fclose(f)	filp_close((f), NULL)
#endif /* loadlib_c */

#endif

