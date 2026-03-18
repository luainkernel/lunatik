/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/* Kernel-space FILE implementation for lua/liolib.c, backed by VFS */

#ifndef lunatik_stdio_h
#define lunatik_stdio_h

#include <errno.h>

#include <linux/printk.h>
#include <linux/fs.h>
#include <linux/slab.h>

#define BUFSIZE			(512)
#define EOF			(-1)
#define feof(f)			((f)->eof)
#define ferror(f)		((f)->err)
#define clearerr(f)		((f)->eof = 0, (f)->err = 0)
#define fflush(f)		(0)
#define bufempty(f)		((f)->bufpos >= (f)->buflen && unlikely(fill(f) == 0))

#define l_getc(f)		getc(f)
#define l_lockfile(f)		((void)(f))
#define l_unlockfile(f)		((void)(f))
#define l_fseek(f, o, w)	seek((f), (o), (w))
#define l_ftell(f)		((f)->pos)
#define l_seeknum		loff_t

typedef struct {
	struct file *filp;
	loff_t pos;
	int bufpos;
	int buflen;
	int err;
	int eof;
	int unget;	/* -1 = empty, 0-255 = pushed-back char */
	char buf[BUFSIZE];
} FILE;

static inline FILE *fopen(const char *path, const char *mode)
{
	if (unlikely(!mode))
		return NULL;

	int flags;
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

	FILE *f = kzalloc(sizeof(FILE), GFP_KERNEL);
	if (unlikely(!f))
		return NULL;

	f->filp = filp_open(path, flags, 0666);
	if (unlikely(IS_ERR(f->filp))) {
		kfree(f);
		return NULL;
	}
	f->unget = -1;
	return f;
}

static inline int fclose(FILE *f)
{
	int ret = filp_close(f->filp, NULL);
	kfree(f);
	return ret ? EOF : 0;
}

static inline int fill(FILE *f)
{
	ssize_t n = kernel_read(f->filp, f->buf, BUFSIZE, &f->pos);

	f->bufpos = 0;
	if (unlikely(n <= 0)) {
		f->eof = (n == 0);
		f->err = (n < 0);
		f->buflen = 0;
		return 0;
	}

	f->buflen = (int)n;
	return (int)n;
}

static inline int getc(FILE *f)
{
	if (unlikely(f->unget >= 0)) {
		int c = f->unget;
		f->unget = -1;
		return c;
	}

	return bufempty(f) ? EOF : (unsigned char)f->buf[f->bufpos++];
}

static inline int ungetc(int c, FILE *f)
{
	if (unlikely(c == EOF))
		return EOF;
	f->eof = 0;
	f->unget = c;
	return c;
}

static inline size_t fread(void *ptr, size_t sz, size_t nmemb, FILE *f)
{
	size_t total;
	if (unlikely(sz == 0 || (total = sz * nmemb) == 0))
		return 0;

	size_t done = 0;
	char *dst = (char *)ptr;
	if (unlikely(f->unget >= 0)) {
		dst[done++] = (char)f->unget;
		f->unget = -1;
	}

	while (done < total) {
		int avail = f->buflen - f->bufpos;
		if (unlikely(!(avail || (avail = fill(f)))))
			break;

		int n = (int)min_t(size_t, avail, total - done);
		memcpy(dst + done, f->buf + f->bufpos, n);
		f->bufpos += n;
		done += n;
	}
	return done / sz;
}

static inline size_t fwrite(const void *ptr, size_t sz, size_t nmemb, FILE *f)
{
	size_t total;
	if (unlikely(sz == 0 || (total = sz * nmemb) == 0))
		return 0;

	ssize_t n = kernel_write(f->filp, ptr, total, &f->pos);
	if (unlikely(n < 0)) {
		f->err = 1;
		return 0;
	}

	return (size_t)n / sz;
}

static inline int seek(FILE *f, loff_t off, int whence)
{
	loff_t ret = vfs_llseek(f->filp, off, whence);

	if (unlikely(ret < 0)) {
		f->err = 1;
		return -1;
	}

	f->pos = ret;
	f->bufpos = 0;
	f->buflen = 0;
	f->unget = -1;
	return 0;
}

#endif

