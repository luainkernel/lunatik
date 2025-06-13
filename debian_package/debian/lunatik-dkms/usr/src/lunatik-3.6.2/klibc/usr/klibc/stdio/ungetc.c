/*
 * ungetc.c
 */

#include "stdioint.h"

int ungetc(int c, FILE *file)
{
	struct _IO_file_pvt *f = stdio_pvt(file);

	if (f->obytes || f->data <= f->buf)
		return EOF;

	*(--f->data) = c;
	f->ibytes++;
	return c;
}
