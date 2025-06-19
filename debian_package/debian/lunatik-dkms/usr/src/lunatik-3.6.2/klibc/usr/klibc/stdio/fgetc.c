/*
 * fgetc.c
 */

#include "stdioint.h"

int fgetc(FILE *file)
{
	struct _IO_file_pvt *f = stdio_pvt(file);
	unsigned char ch;

	if (__likely(f->ibytes)) {
		f->ibytes--;
		return (unsigned char) *f->data++;
	} else {
		return _fread(&ch, 1, file) == 1 ? ch : EOF;
	}
}
__ALIAS(int, fgetc_unlocked, (FILE *), fgetc)
