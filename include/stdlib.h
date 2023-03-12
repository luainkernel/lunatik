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

#ifndef lunatik_stdlib_h
#define lunatik_stdlib_h

#include <linux/slab.h>
#define abort()		panic("Lua has aborted!")
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

