/*
 * fdopen.c
 *
 * Common code between fopen(), fdopen() and the standard descriptors.
 */

#include "stdioint.h"

FILE *stdin, *stdout, *stderr;

/* Doubly-linked list of all stdio structures */
struct _IO_file_pvt __stdio_headnode =
{
	.prev = &__stdio_headnode,
	.next = &__stdio_headnode,
};

FILE *fdopen(int fd, const char *mode)
{
	struct _IO_file_pvt *f;
	const size_t bufoffs =
		(sizeof *f + 4*sizeof(void *) - 1) &
		~(4*sizeof(void *) - 1);

	(void)mode;

	f = zalloc(bufoffs + BUFSIZ + _IO_UNGET_SLOP);
	if (!f)
		goto err;

	f->data = f->buf = (char *)f + bufoffs;
	f->pub._IO_fileno = fd;
	f->bufsiz = BUFSIZ;
	f->bufmode = isatty(fd) ? _IOLBF : _IOFBF;

	/* Insert into linked list */
	f->prev = &__stdio_headnode;
	f->next = __stdio_headnode.next;
	f->next->prev = f;
	__stdio_headnode.next = f;

	return &f->pub;

err:
	if (f)
		free(f);
	errno = ENOMEM;
	return NULL;
}

void __libc_init_stdio(void)
{
	stdin  = fdopen(0, NULL);
	stdout = fdopen(1, NULL);
	stderr = fdopen(2, NULL);
	stdio_pvt(stderr)->bufmode = _IONBF;
}
