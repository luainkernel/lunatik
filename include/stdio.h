/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_stdio_h
#define lunatik_stdio_h

#include <linux/fs.h>
#include <linux/printk.h>
#include <linux/slab.h>

#define EOF		(-1)

#ifdef liolib_c

#define LUAFILE_BUFSIZE	512

typedef struct {
	struct file *filp;
	loff_t pos;
	char buf[LUAFILE_BUFSIZE];
	int bufpos;
	int buflen;
	int err;
	int eof;
	int unget;	/* -1 = empty, 0-255 = pushed-back char */
} FILE;

static inline FILE *fopen(const char *path, const char *mode)
{
	int flags;
	FILE *f;

	if (!mode || !mode[0])
		return NULL;
	switch (mode[0]) {
	case 'r':
		flags = (mode[1] == '+') ? O_RDWR : O_RDONLY;
		break;
	case 'w':
		flags = (mode[1] == '+') ? O_RDWR | O_CREAT | O_TRUNC
					 : O_WRONLY | O_CREAT | O_TRUNC;
		break;
	case 'a':
		flags = (mode[1] == '+') ? O_RDWR | O_CREAT | O_APPEND
					 : O_WRONLY | O_CREAT | O_APPEND;
		break;
	default:
		return NULL;
	}
	f = kzalloc(sizeof(FILE), GFP_KERNEL);
	if (!f)
		return NULL;
	f->filp = filp_open(path, flags, 0666);
	if (IS_ERR(f->filp)) {
		errno = -(int)PTR_ERR(f->filp);
		goto err;
	}
	f->unget = -1;
	return f;
err:
	kfree(f);
	return NULL;
}

static inline int fclose(FILE *f)
{
	int ret = filp_close(f->filp, NULL);

	kfree(f);
	return ret ? EOF : 0;
}

static inline int fill(FILE *f)
{
	ssize_t n = kernel_read(f->filp, f->buf, LUAFILE_BUFSIZE, &f->pos);

	if (n <= 0) {
		f->eof = (n == 0);
		f->err = (n < 0);
		f->bufpos = 0;
		f->buflen = 0;
		return 0;
	}
	f->bufpos = 0;
	f->buflen = (int)n;
	return (int)n;
}

static inline int getc(FILE *f)
{
	if (f->unget >= 0) {
		int c = f->unget;

		f->unget = -1;
		return c;
	}
	if (f->bufpos >= f->buflen && fill(f) == 0)
		return EOF;
	return (unsigned char)f->buf[f->bufpos++];
}

#define l_getc(f)		getc(f)
#define l_lockfile(f)		((void)0)
#define l_unlockfile(f)		((void)0)

static inline int ungetc(int c, FILE *f)
{
	f->unget = c;
	return c;
}

static inline size_t fread(void *ptr, size_t sz, size_t nmemb, FILE *f)
{
	size_t total = sz * nmemb;
	size_t done = 0;
	char *dst = (char *)ptr;

	while (done < total) {
		int c = l_getc(f);

		if (c == EOF)
			break;
		dst[done++] = (char)c;
	}
	return done / sz;
}

static inline size_t fwrite(const void *ptr, size_t sz, size_t nmemb, FILE *f)
{
	ssize_t n = kernel_write(f->filp, ptr, sz * nmemb, &f->pos);

	if (n < 0) {
		f->err = 1;
		return 0;
	}
	return (size_t)n / sz;
}

static inline int seek(FILE *f, loff_t off, int whence)
{
	loff_t ret = vfs_llseek(f->filp, off, whence);

	if (ret < 0) {
		f->err = 1;
		return -1;
	}
	f->pos = ret;
	f->bufpos = 0;
	f->buflen = 0;
	f->unget = -1;
	return 0;
}

#define l_fseek(f, o, w)	seek((f), (o), (w))
#define l_ftell(f)		((f)->pos)
#define l_seeknum		loff_t

#define feof(f)			((f)->eof)
#define ferror(f)		((f)->err)
#define clearerr(f)		((f)->eof = 0, (f)->err = 0)
#define fflush(f)		0

#endif /* liolib_c */

#endif

